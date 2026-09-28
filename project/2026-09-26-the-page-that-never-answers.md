# The page that never answers

*2026-09-26, leaf `DpQmXu`. The suite wedge — a full `swift test` stopped at 0 % CPU with
no frame of ours but the viewer's poll loop — traced to the test suite's calls into a
headless WebKit page, which are completion handlers with no deadline. That such a call can
wedge the run exactly as observed is proven; that it *did*, in the six recorded wedges, is
the best-supported reading, not a proof. What is **proven**
and what is **best-supported** are marked as such; the failure is invisible by
construction, so the distinction matters.*

> **Updated 2026-09-26 (leaf `QZ41uc`):** the deadline now lives in SleepyHollow, not in
> Woodcase's tests. `PageHost.evaluate(_:arguments:in:budget:)`, the console count at the
> end of `PageHost.load`, and the new `PageHost.snapshot(_:budget:)` (which
> `ShotOperation` now goes through) each wait at most the host's `callBudget` —
> `LoadOptions.callBudget`, default `LoadOptions.defaultCallBudget` = 60 s — or a
> per-call `budget:`, and then throw `SleepyError` of kind `.timeout` naming the call. The
> caller's cancellation ends the wait the same way. A call given up on is recorded in
> `PageHost.abandonedCall`, and `WebViewTestHarness`'s host pool discards such a host
> instead of handing it to the next render. `BoundedWait` therefore left
> `WoodcaseViewerTests` (its only use there was bounding page calls) and no longer wraps
> any page call in `WoodcaseTests`, where it stays for the activity-log feed and the curl
> fetcher. `boundedLoad` / `boundedEvaluate` keep their names but no longer carry a
> deadline of their own: what they still add is recording a timeout as an issue naming the
> call, because every bench's `ask` swallows errors. The table below and "The fix" describe
> the state this leaf found; "What would close the question" is done.

## The shape every wedge sample shares

Six occurrences since 2026-09-07 (the job notes on `DpQmXu`), five sampled. Every sample
has the same threads: the main thread idle in `CFRunLoopRun`, `com.apple.NSEventThread`,
`WebCore: Scrolling`, `Log work queue`, and — the only frames of ours —
`ChangeCoordinator.start(watcher:)`'s follow loop polling the activity log. A WebKit view
exists, a viewer server is running, and whatever the in-flight test is awaiting has no
thread. The newest sample (`local/wedges/2026-09-26-Gusv9b-sample.txt`) is of the
`WoodcaseViewerTests` bundle alone (its binary images hold `gusv9b.WoodcaseViewerTests`
and no other test bundle), so the stuck await is one that bundle makes.

## Proven: a page call can suspend a test forever, and looks exactly like the wedge

The browser tests reach the page through SleepyHollow's `PageHost`:

| Call | What it awaits | Deadline |
|---|---|---|
| `PageHost.evaluate` | `WKWebView.callAsyncJavaScript`'s completion | none |
| `PageHost.load` | navigation (budgeted), then `evaluate` once more to count console errors | navigation only |
| `ShotOperation.execute` | `WKWebView.takeSnapshot`'s completion | none |

Built on demand in `PageDeadlineTests`: evaluating
`await (window.__never = new Promise(() => {})); return 1;` suspends the test for good. The
run was killed by its watchdog, and a `sample` of the orphaned host
(`DpQmXu-red3-sample.txt`, not kept) shows the four threads above and **no frame of ours**
— the wedge's signature, minus the poll loop only because that test starts no server.

One subtlety that cost a round: WebKit *does* fail a call whose promise has been garbage
collected (`WKErrorDomain` 4, "Completion handler for function call is no longer
reachable"). `await new Promise(() => {})` therefore returns an error in a few seconds;
only a promise something still holds, or a content process that never answers at all,
hangs.

## Observed: under load, real snapshots take minutes to answer

The first full run with deadlines in place (load average ~460, other agents building):
five `takeSnapshot` calls in the `WoodcaseTests` WebView suites (`WebViewTestHarness`,
`WebView Regression`, `React paint WebView`) did not answer within 120 s; a soak run at
load ~240 repeated it for three. They all expired in the same millisecond — issued together
once a starved main actor let the tests through. That first read as *lost* callbacks, and
was wrong: rerun at load ~240 with a 540 s deadline, the same tests' snapshots did answer,
with `WKErrorDomain` Code=1 "An unknown error occurred" — the load flake
[stroke paints](2026-09-26-stroke-paints.md) also met. So the snapshots are slow failures
under load, not proven hangs, and the harness now allows its budget plus 240 s. The same
suites pass alone at load ~110 in 18 s.

## Best-supported, not proven: the viewer bundle's wedges were a lost `evaluate` or `load`

No wedge of the viewer bundle has been caught in the act with the deadlines in place. The
argument is by elimination: the only awaits that bundle makes on callbacks it does not own
are the page calls above and the server's Network.framework callbacks, and the latter have
been behind `ResumeOnce` since 2026-08-31. The fourth wedge's verbose log had
`ViewerBrowserTests` "Clicking a box on the artboard map focuses that artboard" among its
last-started tests — a test that evaluates while a click it started is navigating the page.
If a viewer-bundle wedge recurs now, it will fail by name ("evaluate `…` did not finish
within 60 seconds") instead; that sentence is what would prove or refute this section.

## The fix: a deadline we own on every page call

- **`BoundedWait` abandons a job instead of waiting for it.** The old form raced the job in
  a task group, and a task group cannot return until every child has — so it could never
  bound the one kind of job this is for, a completion handler that ignores cancellation.
  Its doc comment said as much ("will still hang"), and was right about the code but wrong
  that nothing could be done: the job now runs in a task of its own and the caller waits on
  a continuation that the job, the deadline, or the caller's own cancellation resumes,
  whichever is first. `BoundedWaitTests` holds the cases; the red run was a hang.
- **Every browser test goes through `boundedLoad` / `boundedEvaluate`**
  (`Tests/WoodcaseViewerTests/PageHost+Deadline.swift`), which record an expiry as an issue
  naming the call — every bench's `ask` swallows errors, so a thrown error alone would name
  nothing. `PageDeadlineTests` has a tripwire that fails on any raw `host.load(` or
  `host.evaluate(` in that target.
- **`WebViewTestHarness.render` bounds each page call** at the harness budget plus 60 s.
- **Suites that await a page, a server or a feed carry `.hangGuard`**, an eight-minute
  `.timeLimit`. Because `BoundedWait` now honours cancellation, the limit *ends* a test
  stuck in a page call rather than only reporting it; a test stuck in some other await it
  does not know about still gets named in the log when the limit passes.

`BoundedWait` is duplicated in `WoodcaseTests` and `WoodcaseViewerTests`: two test targets
cannot share a helper without a test-support target, and adding one to `Package.swift` was
out of scope for this leaf.

## Why eight minutes

A test's wall time is not its own work. Every browser test runs on the main actor,
interleaved with every other, so the slowest test reports most of the whole run — 78 s of a
94 s run in the 2026-09-08 suite logs (`local/suite-logs/`, the `passed after` lines). A run
at load 200 takes about 3 minutes; at load 280, 11. The agents' watchdog kills a run at
10 minutes, so a limit at or beyond it names nothing. Eight minutes is past every healthy
test the watchdog lets finish and short of the watchdog. Swift Testing counts limits in
whole minutes.

## What would close the question for good

> **Done 2026-09-26 (leaf `QZ41uc`)** — see the Updated block at the top. The red for it
> is SleepyHollow's `PageHostDeadlineTests`: before the change its never-answering
> evaluation hung the filtered run until the watchdog, and a `sample` of the orphaned
> host held the four threads above and no frame of ours.

The deadline belongs in `PageHost` itself: SleepyHollow's `evaluate` and `ShotOperation`
should bound their completion handlers the way `navigate` already bounds the navigation,
so every consumer — the `sleepy` CLI included — gets it. (Woodcase itself only uses
SleepyHollow from its tests.) That is a change to another repo and was left for its own
leaf.
