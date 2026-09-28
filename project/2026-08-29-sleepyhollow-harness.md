# Replacing the WebView test harness with SleepyHollow

**Date:** 2026-08-29. **Decision (Ben):** add SleepyHollow (`../SleepyHollow`, Ben's headless-WebKit library, macOS 12+) as a **test-target-only** dependency and re-implement `Tests/WoodcaseTests/WebViewTestHarness.swift` on its `PageHost`, keeping the harness's public shape so the ~20 MAE tests and `performance/mae-baseline.csv` do not change.

**Why.** The harness is 231 lines of `WKWebView` plumbing — offscreen view, `loadFileURL(_:allowingReadAccessTo:)`, a `window.__READY__` poll, JS-error capture, `takeSnapshot` — and it is where the WebView flake has lived (READY timeouts, read-access roots, the phantom `icon-test.html` fixture removed in `8f97ba5`). SleepyHollow has each of those as a named, tested piece (`PageHost.load → PageFacts`, `WaitCondition`, `ConsoleCapture`, `IdleWatch`, the shot pipeline with explicit `ViewportSize`/`ShotScale`), on the same system WebKit, so the pixels stay the same pixels.

**Dependency shape.** `.package(url: "https://github.com/bensyverson/sleepyhollow.git", revision: "35c1b0c…")` — pinned to `origin/main` as of 2026-08-29 (the local checkout is one README-only commit ahead). A pinned URL, not a path: a path dependency would couple Woodcase's test run to whatever state the sibling checkout is in.

> Corrected the same day: the first draft said `path: "../SleepyHollow"` because the local HEAD was not on a remote branch; Ben confirmed the repo is on GitHub and only the last commit was unpushed.

> Corrected after the implementation landed (2026-08-29): three of the pieces named above did not survive contact.
>
> - **`WaitCondition` is not what waits for `__READY__`.** `.predicate("window.__READY__ === true")` works in isolation, but `WaitEngine` re-checks it *from the host*, on the main actor, every 50 ms. Woodcase's suite saturates the main actor with parallel renderer work, and a full `swift test` starved that poll into two timeouts (`StatCard`, and the icon-font harness test at a 10 s budget) that the pages had not earned. The harness therefore loads with `wait: nil` and keeps the old design's *page-side* push: an `InjectedScript` polls `window.__READY__` with `setTimeout(…, 16)` and posts to a `ready` script-message handler, which the harness races against its own timeout. This is the same reason the retired code carried the comment about `Timer` versus `Task.sleep`.
> - **No read-access root is needed, and SleepyHollow has none.** There is no equivalent of `loadFileURL(_:allowingReadAccessTo:)` anywhere in its API; `PageHost.load` calls `webView.load(URLRequest(url:))`. Measured: that still loads a `file:` document *and* its relative subresources in sibling and parent directories, which is everything these fixtures need, so the `allowingReadAccessTo:` parameter is now unused and kept only for the callers.
> - **`swift-argument-parser` had to move to 1.8.2.** SleepyHollow's `sleepy` target uses `@Option(defaultAsFlag:)`, which 1.7.1 (Woodcase's old pin) does not have, and `swift build` builds every product in the graph. `swift package update swift-argument-parser` fixes it; `WoodcaseCommand` builds and its tests pass on 1.8.2.
>
> What did hold: `PageHost` + `LoadOptions` + `ViewportSize` for the page and its viewport, `ConsoleCapture`/`ConsoleOperation` for JS-error surfacing, and `ShotOperation` + `ShotScale(factor: 2)` + `ShotCapture` for the capture — with every MAE row byte-identical to the baseline.

**Acceptance.** After the swap, a full `swift test` writes a `performance/mae-test.csv` that is byte-identical (after sorting) to the baseline; if any MAE moves, the cause is a scale or viewport mismatch to fix, not a threshold to loosen. The `sleepy` CLI is not used by the tests; it is a tool for agents (`sleepy shot`, `sleepy console` on generated viewer HTML) and goes in `project/agents/harness.md`'s project notes via gotchas if it earns it.

```yaml
tasks:
  - title: Test infrastructure
    desc: |
      Ongoing work on the test harnesses, snapshot tooling and CI gates — not tied to a feature plan.
    children:
      - title: Re-implement WebViewTestHarness on SleepyHollow
        desc: |
          See project/2026-08-29-sleepyhollow-harness.md. Add SleepyHollow as a test-target-only dependency pinned to a GitHub revision, replace WebViewTestHarness's WKWebView internals with PageHost (load, wait for window.__READY__, console errors, snapshot to CGImage), keep render(fileURL:viewportSize:allowingReadAccessTo:timeout:) and its error cases, and prove the MAE baseline is byte-identical.
        criteria:
          - performance/mae-test.csv matches the baseline byte-for-byte after sorting
          - WebViewTestHarness.swift no longer imports WebKit directly
          - The dependency is on the test target only; the library builds without it
```
