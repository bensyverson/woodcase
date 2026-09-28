# Suite speed: whole-module SwiftUI batches and concurrent WebView renders

**Date:** 2026-09-28. **Leaves:** `MeFlNF`, `cWdP3b`. **Result:** `swift test` went from about **8½ minutes to 2 minutes 51 s**
wall (171 s) on a shared 8-core Mac at load 20–35; `WoodcaseTests` from **909 s to 127 s**. Every gate is unchanged: the
same boards, references, thresholds and baselines. Only scheduling moved.

The machine was never quiet. Other sessions' Go test suites, Zoom and Granola kept the load average between 15 and 60
all day, so every figure below names its load; compare figures that share one.

## Reproducing

```sh
# sandbox off — the Swift toolchain fails inside the Bash sandbox
/usr/bin/time -p swift test --skip-build > run.log 2>&1   # whole run
scripts/suite-times run.log                               # slowest suites and tests (a log run without --quiet)
WOODCASE_TEST_PROFILE=1 swift test --skip-build --filter ReactRenderWebViewTests  # per-phase PROFILE lines
WOODCASE_TEST_WEBVIEW_WIDTH=8 swift test --skip-build     # the render gate's width, default 4
scripts/soak-tests 4 soak.log --load 2                    # the loaded soak
```

## 1. The SwiftUI render batch compiled one file at a time

`SwiftUIRenderBatch` hands `xcrun swiftc` 334 generated files. Without `-wmo`, `swiftc` starts one frontend per file and
each re-parses the whole module, so the cost is files × module size. The morning's full suite printed
`SwiftUIRenderBatch: build 788.7 s, typecheck 731.4 s` (load 30–55). The same sources type-checked whole-module in
12.6 s of CPU, 34 s wall (load ~55), with no function body over 91 ms
(`-Xfrontend -warn-long-function-bodies=50`). With `-wmo` in `SwiftUIRenderBatch.compile(floor:)`, which all four
batches share, the four batch suites alone took 92 s with build 41.5 s and type-check 19.5 s (load 18–25). In the full
suite it was build 20.6 s and type-check 12.6 s.

This corrects the record: leaf `T5l1ul` (wave-nine handoff) found "typecheck dominates the batch" and read it as the
emitted code being slow to type-check. The emitted code is cheap. Annotating it (`Gradient.Stop(...)` for `.init(...)`,
leaf `RNfBuL`) is rule compliance, not speed.

## 2. What the suite was waiting on

With the batch fixed, `WoodcaseTests` still took 255–286 s. Two traps cost time finding why:

- **Swift Testing's per-test durations include queueing.** Every test is started up front and timed from then, so a
  test that waits for a free thread is charged the wait. One run had 749 tests, from lint findings to CRDT inits,
  all "taking" 74.9–75.1 s; another had 2,670 at 48 s. They measure the queue, not the tests.
- **The throw-ladder was a red herring.** A mid-stall `sample` showed threads in `_os_unfair_lock_lock_slow` under
  Swift Testing's `Backtrace._willThrow`, fed by `AnyCodable.init(from:)`, which decodes by trying each type and
  catching the throw. Turning capture off (`SWT_SWIFT_ERROR_BACKTRACING_ENABLED=0`) moved the suite from 266 s to
  255 s, which is noise. The ladder is still waste (leaf `NQxgi0`).

The honest measure was CPU: the test process used 350 s of CPU over about 287 s of wall, 1.2 of 8 cores
(`ps -o time` at the end of a run). The suite was waiting. Its wall time equalled its slowest suite,
`React render WebView`: 283 boards rendered strictly one at a time (`.serialized`, `@MainActor`), 148 s alone (load
11–17). Per board, from `WOODCASE_TEST_PROFILE` (283 boards, load 11–17):

| phase | total | avg / board | where |
|---|---|---|---|
| WebKit page load | 40.1 s | 142 ms | content process; main actor idle |
| page fonts | 44.6 s | 158 ms | content process; main actor idle |
| MAE diffs (two per board) | 18.1 s | 64 ms | main actor |
| snapshot, errors, host | 4.2 s | 15 ms | main actor |
| emit, layout, CG render (unprofiled remainder) | ~41 s | ~145 ms | main actor |

## 3. Concurrent renders

- **Off the main actor.** Building a page (parse, emit, layout, HTML), the CG render and the pixel diffs are
  `@concurrent nonisolated` functions now, in all five React WebView suites
  (`PenSnapshotTestHelpers.concurrentMeanAbsoluteError`, `WebViewTestPage`). Only the WebKit call stays on the main
  actor. `WebView Regression` moved only its diffs: its CG render reads a `@MainActor` shared fixture.
- **Bounded, not serialized.** `.serialized` is gone from those six suites. `WebViewTestHarness.render` passes
  `WebViewRenderSlots`, one process-wide gate of four renders in flight, which a render waits on before its load
  budget starts. `WOODCASE_TEST_WEBVIEW_WIDTH=1` serializes every render again.

| run | `WoodcaseTests` | `swift test` wall | load |
|---|---|---|---|
| before, `-wmo` only | 255–286 s | — | 15–30 |
| React render concurrent | 162 s | 211 s | 10–45 |
| all six suites | **127 s** | **171 s** | 20–35 |
| all six, width 8 | 146 s, `set` verb budget failed | 197 s | 18–30 |

`React render WebView` alone went from 148 s to 37 s at width 4 (load 5–14) and 38 s at width 8 (load 37). Width 4
stays: 8 was no faster in the full suite and tripped a wall-clock budget.

What bounds the suite now is the shared render queue: every WebView suite ends together at about 126 s. The next lever
is per-render cost. A page reloads its fonts on every navigation (158 ms), and `WebView Regression`'s CG render is
still on the main actor.

## 4. The loaded soak

`scripts/soak-tests 4 soak.log --load 2` (other sessions' load ~30–50 on top): every WebView test passed in all four
runs, 267–330 s each. So the flake `.serialized` guarded against did not return.

Two runs failed anyway, on performance budgets, whose debug run then still failed past 4 × its limit:

| run | budget | best of 5 | debug limit | the same budget, moderate load |
|---|---|---|---|---|
| 3 | `tree` of `woodcase-app.pen` | 3062.8 ms | 750 ms | 328.6 ms |
| 4 | `set` verb on `woodcase-app.pen` | 2765.8 ms | 500 ms | 1247.2 ms |

Nothing hung: the commands finished, slowly, sharing the cores with four WebKit pages, the render and diff work now off
the main actor, the soak's synthetic load and other sessions. The minimum of five is already the most load-tolerant
statistic (a median would be worse), and sustained load inflates every repetition together. Concurrent renders make
the suite busier by design, so they raise the odds of this.

Ruling (Ben, 2026-09-28): a debug run only ever warns. `PerformanceBudget.check` lost its 4 × advisory ceiling, and
its `BUDGET-ADVISORY` line now says how many times over and names `swift test -c release --filter Performance`, the
run where a budget fails. See `WoodcasePerformance.md`, "A debug budget is advisory".
