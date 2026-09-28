# Making the WebView regression suite fast

**Date:** 2026-08-29. **Leaf:** `VY4EA`. **Result:** `WebViewRegression` went from **18.7 s to 8.0 s** (best of several runs each, quiet machine), with every MAE row byte-identical to `performance/mae-baseline.csv`. The full suite is **17.0 s / 1837 tests**.

Nothing about what the suite measures changed: same `captureScale: 2`, same viewports, same thresholds, same two pipelines, same `.serialized`. The whole saving is work that was being done eleven times instead of once, plus a WebKit resource cache that was being thrown away between pages.

## Reproducing

```sh
# timings (sandbox off — the Swift toolchain fails inside the Bash sandbox)
swift test --filter WebViewRegression

# per-phase profile: one `PROFILE <scope> <phase> <milliseconds>` line per phase
WOODCASE_TEST_PROFILE=1 swift test --filter WebViewRegression 2>&1 | grep PROFILE

# A/B the page-host reuse with everything else held constant
WOODCASE_TEST_PROFILE=1 WOODCASE_TEST_NO_HOST_POOL=1 swift test --filter WebViewRegression
```

Aggregate a profile with:

```sh
grep '^PROFILE' run.log | awk '{s[$3]+=$4; n[$3]++} END {for (k in s) printf "%-12s %8.0f ms  %6.0f avg (n=%d)\n", k, s[k], s[k]/n[k], n[k]}' | sort -k2 -nr
```

`PhaseStopwatch` (`Tests/WoodcaseTests/PhaseStopwatch.swift`) is left in behind `WOODCASE_TEST_PROFILE`; off, a lap is one `Bool` comparison. Instrumentation that has to be re-added every time somebody measures gets re-added wrong.

## A warning about every number below

Four other agents were building in sibling worktrees on this machine for the first half of this work, and the effect is larger than the effect being measured. The same unchanged suite measured **50.1 s, 33.6 s, 25.7 s, 18.7 s, 18.9 s** over half an hour as the machine drained. **Only the last two are the suite; the first three are the neighbours.** Every before/after pair below is either a minimum over several runs, or an A/B taken back-to-back in the same minute.

This also corrects the premise this leaf was filed on. The leaf recorded "~95 s full suite, ~78 s for `WebViewRegression`, measured 2026-08-29". Those were load-inflated: the true pre-change figure on a quiet machine is **18.7 s** for the suite, **~26 s** for the full run. The work was still worth doing — it is a 2.2× cut — but it was never a 78 s suite.

## The profile, before

`WOODCASE_TEST_PROFILE=1 swift test --filter WebViewRegression`, 11 tests. **Taken under four-agent load**, so read the ranking and the proportions, not the absolute milliseconds.

| phase | total | avg / test | what it is |
|---|---|---|---|
| `loadDocuments` | 20442 ms | 1858 ms | parse + resolve + ref-expand the fixture |
| ↳ `expand` | 20723 ms | 1727 ms | `PenRefExpander.expand` + resolve — the whole cost |
| ↳ `parse` | 1163 ms | 97 ms | `PenParser.parse` of 244 KB of JSON |
| ↳ `resolve` | 99 ms | 8 ms | |
| `mae` | 11914 ms | 1083 ms | `PenSnapshotTestHelpers.meanAbsoluteError` |
| `webView` | 10729 ms | 975 ms | the whole of `WebViewTestHarness.render` |
| ↳ `load` | 7609 ms | 692 ms | `PageHost.load` |
| ↳ `fonts` | 1755 ms | 160 ms | `document.fonts.ready` + the fixed 150 ms paint sleep |
| ↳ `host` | 458 ms | 42 ms | `PageHost(options:)` |
| ↳ `snapshot` | 461 ms | 42 ms | `ShotOperation` + decode |
| ↳ `ready` | 340 ms | 31 ms | waiting for `window.__READY__` |
| `layout` | 2342 ms | 213 ms | `PenLayoutEngine.layout` |
| `emit` | 1625 ms | 148 ms | `ReactEmitter.emit` |
| `penRender` | 510 ms | 46 ms | `PenRenderer.render` |
| `saveImages` | 464 ms | 42 ms | two debug PNGs per test |
| `html` | 215 ms | 20 ms | `ReactHarnessBuilder.buildHTML` + writes |
| `analyze` | 200 ms | 18 ms | the three analyzers |

The shape is unambiguous: **43 % of the suite was re-deriving the same fixture** — the same parse, the same ref expansion, the same analysis, the same emitted React, the same layout, eleven times, from a file that cannot change during a run. A further 24 % was one `for` loop.

## What changed

### 1. The fixture is derived once (the bulk of the saving)

New: `Tests/WoodcaseTests/WebViewRegressionFixture.swift`. One `@MainActor` struct holding `raw` / `resolvedOnly` / `expanded`, the three analyses, both emit results (components-only and components+pages, kept separate because `compareComponent` and `compareScreen` genuinely emit different file sets), and both layouts. Built on first use, memoised in a `private static var`; main-actor isolation is what makes the lazy build safe without a lock.

`WebViewRegressionTests.loadDocuments()` is gone. Measured after: the whole derivation is **810 ms, once** (`parse` 29, `resolve` 3, `expand` 515, `analyze` 6, `emit` 93, `layout` 164) against 20.4 s + 2.3 s + 1.6 s + 0.2 s spread across eleven tests before.

A failure is deliberately *not* memoised: a fixture that could not be read should be re-reported to every test that asks, not swallowed once.

### 2. Page hosts are pooled and reused (−1.6 s)

`WebViewTestHarness` built a `PageHost` per render. A `PageHost` is a `WKWebView` with its own **non-persistent** data store, so every render got a cold web content process and an empty resource cache — and every fixture page loads `babel.min.js` (3.0 MB) and `tailwindcss.js` (407 KB) and transpiles the emitted TSX in the browser. Eleven cold Babel compiles.

Now the harness keeps a pool of idle hosts keyed by load budget, checks one out per render and hands it back in a `defer`.

- **Reuse is safe.** `PageHost.load` is built for repeated calls: `isLoading` refuses only a *concurrent* load, and `navigateAndSettle` resets `facts`, `navigationFailure` and `contentProcessFailure` per navigation. The injected scripts (ready-on-error, ready-signal, SleepyHollow's own console capture) are WebKit *user scripts* installed at `init`, so they re-run on every document; `window.__READY__` and the console capture's buffer are page globals, so they die with the document. `messages(named:)` sinks are removed when their stream terminates, so subscribing per render does not accumulate.
- **A pool, not one host.** Two reasons. `PageHost` refuses a concurrent load on one host, and `WebViewTestHarnessTests` is *not* serialized — three of its tests share a 30 s budget and one shares the regression suite's 5 s budget, so a single shared host would have thrown `SleepyError(.usage)` the moment two overlapped. A checked-out host is simply absent from the pool.
- **Keyed by budget** because `PageHost.budget` is `options.budget`, fixed at `init`. A host built for 30 s cannot honour a caller asking to fail after 2. See the SleepyHollow finding below — this is the one thing that forces the pool to be a pool of more than one.

A/B, quiet machine, back to back, everything else identical (`WOODCASE_TEST_NO_HOST_POOL=1` vs not):

| harness phase | host per render | pooled | delta |
|---|---|---|---|
| `host` (creation) | 151 ms / 14 ms avg | 111 ms / 10 ms avg | −40 ms |
| `load` | 2801 ms / 255 ms avg | 1239 ms / 113 ms avg | **−1562 ms (−56 %)** |
| render total | 5055 ms | 3427 ms | −1628 ms |
| **whole suite** | **9.72 s** | **8.09 s** | **−1.63 s** |

Creating the host is not the cost — 14 ms. The cost is the cold cache behind it.

### 3. The MAE loop reads through raw pointers (−~0.5 s)

`PenSnapshotTestHelpers.meanAbsoluteError` summed `abs(Int(a[i]) - Int(b[i]))` over `[UInt8]` arrays — up to 5.3 M channels per comparison, 58 M per suite, in an **unoptimized** build, where `Array.subscript` and the generic `Int.init(UInt8)` are real function calls into `libswiftCore`. It now takes the same sum through `withUnsafeBufferPointer` and `Int32` compare-subtract. The arithmetic is unchanged, so every MAE it reports is unchanged — confirmed by the byte-identical CSV, which this helper also feeds for the eleven non-WebView `pencil-*` snapshot rows.

`extractPixels` (the two `CGContext.draw` calls) is not the cost: 106 ms across the suite against 3310 ms for the loop.

### 4. `.serialized` stays

Deliberately kept on `WebViewRegressionTests`, for a reason the profile does not show. The [SleepyHollow harness finding](2026-08-29-sleepyhollow-harness.md) records that parallel Woodcase renderer work saturating the main actor starved SleepyHollow's `WaitEngine` poll into two timeouts the pages had not earned — which is why the ready signal is page-pushed today. Every phase of this suite is `@MainActor` (WebKit, Core Graphics, the pixel renderer), so unserializing it buys interleaving, not parallelism, at the price of re-opening that flake. The host pool is safe under concurrency either way; that safety is there for `WebViewTestHarnessTests`, which is not serialized, not as a step toward unserializing this one.

## The profile, after

Quiet machine, 8.09 s suite.

| phase | total | avg / test |
|---|---|---|
| `webView` | 3427 ms | 312 ms |
| ↳ `load` | 1239 ms | 113 ms |
| ↳ `fonts` | 1749 ms | 159 ms |
| ↳ `snapshot` | 244 ms | 22 ms |
| ↳ `host` | 111 ms | 10 ms |
| ↳ `errors` | 76 ms | 7 ms |
| ↳ `ready` | 3 ms | 0 ms |
| `mae` | 3417 ms | 311 ms |
| ↳ `diff` | 3310 ms | 301 ms |
| ↳ `extract` | 106 ms | 10 ms |
| `fixture` | 810 ms | once |
| `penRender` | 189 ms | 17 ms |
| `saveImages` | 151 ms | 14 ms |
| `html` | 82 ms | 7 ms |

What is left is real work, in three parts, all roughly equal:

- **3.4 s in the browser**, of which **1.75 s is the harness's fixed `Task.sleep(for: .milliseconds(150))`** after `document.fonts.ready` — 22 % of the whole suite spent waiting for a paint that has probably already happened.
- **3.4 s in the MAE loop**, which is 58 M iterations of unoptimized Swift. Cutting it further means either Accelerate (`vDSP_vfltu8` → `vDSP_vsub` → `vDSP_vabs` → widen to `Double` → `vDSP_sveD`, which is provably exact for integer channel values ≤ 255 summed under 2⁵³, but adds an Apple-only import to a helper with no platform guard) or SWAR over `UInt64` words. Neither is worth the risk of moving a single MAE digit for a suite already 2.2× faster; parked, not forgotten.
- **0.8 s deriving the fixture**, of which 515 ms is `PenRefExpander.expand`. That is a real cost in the library, now paid once instead of eleven times, and it is where to look if the fixture grows.

## Finding for SleepyHollow

Requested by Ben mid-task: whether the seconds are in SleepyHollow, and what to change there.

**They are not.** `PageHost` creation is **14 ms** and the shot pipeline is **22 ms**; both are noise. SleepyHollow's own settle is 0 ms because this harness does not use it. The seconds in `load` are the fixture page's own 3.4 MB of JavaScript, and reusing the host recovered 56 % of them without SleepyHollow changing at all — which is a compliment: `PageHost` is already reuse-correct, and every piece of per-load state it owns already resets on navigation.

Four concrete changes, in the order they would pay:

1. **Let the budget be per-load, not per-host.** `PageHost.budget` reads `options.budget`, fixed at `init`, so a caller that wants a 2 s failure and a caller that wants 30 s cannot share a host. This is the only reason Woodcase's harness needs a pool keyed by budget rather than one host. Change: `func load(_ url: URL, budget: TimeInterval? = nil)`, falling back to `options.budget ?? LoadOptions.defaultBudget`. Cheap, additive, and it collapses a caller-side data structure into nothing.
2. **Let hosts share a cache.** Every `PageHost` gets `WKWebsiteDataStore.nonPersistent()` and its own process, so two hosts share no resource cache and no JS bytecode cache. The measured value of a warm one is **142 ms per page load** on a page with 3.4 MB of scripts. Change: let `LoadOptions` optionally carry a `WKWebsiteDataStore` (and/or a shared `WKProcessPool`) so a caller running many pages can opt into sharing, with the current per-host non-persistent store as the default. This matters for `sleepy shot --sweep` and any batch verb, not just for tests.
3. **A push-based wait condition.** `WaitCondition.predicate(_:)` is re-checked *from the host*, on the main actor, every 50 ms, which is why Woodcase had to hand-roll `readySignalScript` + `waitForSignal` and load with `wait: nil` (recorded in the [2026-08-29 harness finding](2026-08-29-sleepyhollow-harness.md)). Change: `WaitCondition.message(name:)` — settle when the page posts to a named script-message handler. That is ~20 lines in `WaitEngine`, and it would let this harness delete two of its own pieces and stop having a documented reason to avoid a SleepyHollow feature.
4. **A "has painted" signal, to retire the 150 ms sleep.** The harness sleeps a flat 150 ms after `document.fonts.ready` to let a final paint land — 1.75 s of an 8.1 s suite, and a guess in both directions. SleepyHollow already has `IdleWatch` and the CLI has `ObserveRendering`; a `PageHost` operation that resolves when the next paint has committed (`requestAnimationFrame` under `ensureOffscreenWindow()`, or a rendering-update observer) would replace a fixed sleep with an actual condition. Note the constraint it must respect: a headless web view never runs `requestAnimationFrame` unless an operation opts into an offscreen window, which is exactly the trap that makes this worth owning in SleepyHollow rather than in each caller.

Items 1 and 2 are what Woodcase would use tomorrow; 3 and 4 would let the harness shrink.

## Files

- `Tests/WoodcaseTests/PhaseStopwatch.swift` — new; the flag-gated profiler.
- `Tests/WoodcaseTests/WebViewRegressionFixture.swift` — new; the once-per-process fixture derivation.
- `Tests/WoodcaseTests/WebViewTestHarness+HostPool.swift` — new; the pool. Split out because the harness had reached 313 lines with it inline, past the house ceiling; the two injected scripts widened from `private` to internal so the extension can install them.
- `Tests/WoodcaseTests/WebViewTestHarness.swift` — checks a host out and back, laps.
- `Tests/WoodcaseTests/WebViewRegressionTests.swift` — reads the fixture, laps.
- `Tests/WoodcaseTests/PenSnapshotTestHelpers.swift` — pointer-based MAE loop, laps.

`Sources/` is untouched.

## Acceptance

`swift test --quiet` — **1837 tests in 171 suites passed in 17.0 s**. `performance/mae-test.csv` and `performance/mae-baseline.csv` are identical across all 25 rows after sorting by id (`tail -n +2 <file> | sort -t, -k1,1`), including the eleven `pencil-*` rows that share the MAE helper. `swiftformat . --lint` clean.
