# Three load-shaped flakes, and the wait that gives up without looking

*2026-08-31 — leaf `YfptE`*

A loaded soak on `33b65e7` failed 3 of 5 runs, none of them in the browser suites:
`scripts/soak-tests 5 <log> --load 2 --timeout 400` (sibling agents building at the
same time, so the machine was loaded beyond the two synthetic cores). The three
failures were diagnosed from that soak's own per-run logs rather than re-derived,
and none of them is a product bug. All three are budgets, and one of them is a
wait that could not have succeeded.

## What the logs said

| run | test | line |
| --- | --- | --- |
| 1 | `WebViewTestHarnessTests` "Surfaces an uncaught JavaScript error rather than timing out" | `WebViewTestHarnessTests.swift:212` |
| 2, 3 | `PenFileTransactionTests` "Two concurrent transactions serialize…" | `PenFileTransactionTests.swift:310` |
| 3 | `FileWatcherTests` ×3 and `SSEHubTests` "An idle stream gets a heartbeat comment…" | `ViewerFixtures.swift:85` |

## A budget is not an assertion, and both measure the machine

`project/gotchas.md` already warns that a wall-clock *assertion* near the interval
under test measures load rather than behaviour. Two of these three are the other
half of that idea, which the entry did not cover: a **budget** passed *into* the
code under test is just as load-shaped, and it fails in a way that reads like the
product misbehaving rather than like a clock.

- The harness test asked for `timeout: 5.0`, which covers the `PageHost` load and
  the ready-signal wait *together* (`remaining = timeout - elapsed`). What the test
  asserts is *which typed error* comes back — `.javaScriptError`, not `.timeout`.
  The log says exactly what happened: "Expected .javaScriptError, got WebView timed
  out waiting for __READY__ signal". The page's ready signal is pushed by an
  injected script on WebKit's own clock and the stream is subscribed before the
  load, so nothing was missed — five seconds simply ran out first, and the harness
  reported the budget instead of the page. It is now
  `WebViewTestHarness.defaultBudget` (60 s), shared by every render that expects a
  page to work; the one test that *expects* a timeout keeps its own short one.

- `concurrentTransactionsSerialize` asked for `timeout: .seconds(10)` and got a
  genuine `PenFileError.lockTimeout` — "…layout-vertical.pen is locked by another
  process; gave up after 10s". `FileLock.acquire` waits by polling with a 10 ms
  `Task.sleep`, and this suite has been measured resuming a sleep that size twelve
  seconds later, so the waiter got roughly *one* attempt inside its whole window
  while the holder queued on the main actor. Now `.seconds(60)`, named
  `lockBudget` and documented, matching `ViewerFixtures.lockBudget`, which was
  raised for exactly this reason on the viewer side.

Neither `FileLock`, `PenFileTransaction` nor `FileWatcher` behaved incorrectly in
any log line. `FileLockTests`' many `.milliseconds(200)` budgets were checked and
deliberately left alone: every one of them acquires an *uncontended* lock, and
`acquire` attempts before it checks the deadline, so those budgets can never be
spent.

## The wait that could not succeed

The four `ViewerFixtures.swift:85` failures shared one helper, `waitUntil`, and it
had a hole worth more than the bound it was given:

```swift
let deadline = ContinuousClock.now + bound
while ContinuousClock.now < deadline {
    if await condition() { return }
    try? await Task.sleep(for: poll)
}
Issue.record("timed out waiting for \(description)")
```

The deadline is checked *before* the condition and the condition is never
evaluated again after the loop. That is fine when `poll` means what it says. Under
this suite it does not: a 50 ms poll sleep resuming tens of seconds late makes the
real granularity tens of seconds, so a condition that came true at 25 s of a 30 s
bound is reported as a timeout nothing earned — and the report names the *watcher*
or the *hub*, never the wait. Reproduced deterministically as
`await waitUntil("…", within: .zero) { true }`, which recorded a timeout for a
condition that was already true; that is `WaitUntilTests.alreadyTrueHoldsAtASpentBound`,
and it was red before the fix.

`waitUntil` now evaluates the condition once more after the deadline, and answers
whether it held rather than returning nothing; its default bound is
`ViewerFixtures.waitBudget` (60 s), the same "not hung" scale as the `lockBudget`
and `requestBudget` beside it. Returning the answer lets a caller skip the
assertions that would only restate the same failure — `FileWatcherTests` had two
tests reporting one late report as two problems.

## Verification

Green: `swift test --quiet` — 3354 tests in 342 suites (3351 before, plus the three
new `WaitUntilTests`). Loaded soak after the fix, on the same machine and with a
sibling agent building in parallel (load average 13–15 throughout):
`scripts/soak-tests 5 <log> --load 2 --timeout 400` — **5/5 runs passed**, runs of
53–69 s. The same command on `33b65e7`, the commit this change sits on, passed 2/5.
An earlier 5/5 on the same command covered a shape one refactor back, so the
figure quoted here is the second soak, on the code as it stands.

## The general rule

A bound is a claim about hanging, never about speed. Whether it is asserted after
the fact or handed to the code as a `timeout:`, put it at the scale of "this is
wedged" — tens of seconds here — and make the failure name the observable outcome.
And a poll loop that stops at its deadline must look once more before it gives up:
the deadline bounds how long you wait, not whether you check.
