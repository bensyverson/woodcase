# The await that cannot resume

*2026-08-31, leaf `3uBxi`. The third face of the suite hang — 0 % CPU, no frames of ours —
reproduced on demand, diagnosed, and closed at the seam that could produce it. What is
**proven** and what is **best-supported** are marked as such throughout; the distinction
matters, because the failure mode is invisible by construction.*

## Reproducing it on demand

The wedge was reported as needing multi-agent build load. It does not: it needs *load*,
and the soak harness can supply that.

```
scripts/soak-tests 3 <log> --load 2 --timeout 180   # 3/3 passed, 55/85/82 s
scripts/soak-tests 2 <log> --load 6 --timeout 280   # 1/2 — run 1 TIMEOUT at 280 s
```

Both sandbox off, on an 8-core / 16 GB machine with no sibling agents building
(`ps -Ao pid,etime,pcpu,comm | grep swift-frontend` = 0). `--load 2` occupies a quarter of
the machine and never wedged; `--load 6` occupies three quarters and wedged on the first
run. **The variable is contention, not other agents**, which makes this reproducible by
anybody with the harness. Budget about ten minutes a pair of runs.

The captured sample is the one the harness takes automatically when its watchdog fires.

## What the fresh sample says

Physical footprint 139 MB — so not the out-of-memory face. 0 % CPU. Threads: the main
thread idle in `CFRunLoopRun` under `swift_task_asyncMainDrainQueue`; three worker threads
parked in `__workq_kernreturn`; a live `com.apple.network.connections` queue running
`nw_context_purge_endpoints`; and the only frames of ours, on three separate cooperative
threads, are `ChangeCoordinator.start(watcher:)`'s `for await` over
`ActivityReader.Follow.Iterator.next()`.

Read correctly, per [the follow finding](2026-08-31-follow-is-a-value.md): those poll
loops are the **survivors**, not the culprit. What they prove is that at least one
`ViewerServer` was still running long after the test that made it should have finished —
the suite stops servers with `defer { Task { await bench.stop() } }` in 88 places, a
*request* to stop rather than a stop. And the live Network queue proves the process still
held Network.framework endpoints. Neither can show what was suspended, because nothing
suspended can be shown.

> **Correction to the issue text.** `3uBxi` says the preserved sample
> `local/wedge-samples/2026-08-31-integrator-run-46108.txt` has a "live
> `com.apple.network.connections` queue". It does not — that sample has no network queue
> at all; it is the row-1 host with two `ActivityReader.follow` poll loops. The network
> queue belongs to the *other* sample (pid 48269) described in the follow finding. The
> new sample taken for this leaf has both, which is the first time the two signatures
> have appeared together.

## The seam, audited

`Sources/WoodcaseViewer/Server/` made exactly three `withCheckedContinuation` calls, and
every one of them was unbounded and uncancellable:

| Where | Awaited | Resumed by |
|---|---|---|
| `HTTPServer.start(port:)` | `NWListener` state | `.ready`, `.failed`, `.cancelled` |
| `HTTPConnection.send` | `NWConnection.send` completion | the completion, always |
| `NetworkSSEWriter.send` | `NWConnection.send` completion | the completion, always |

Two things were wrong with that table.

**A reachable state resumed nothing.** The listener handler's `switch` ended in
`default: break`, which swallowed `.setup` (correct — it precedes an answer) and
`.waiting` (not correct). `NWListener` reports `.waiting` for a port it cannot have *yet*
and then retries on its own schedule, indefinitely. A listener that sat in `.waiting` left
`start` suspended for the life of the process, and there was no timeout, no cancellation
path, and no `stop()` that could reach it — `ViewerServer.stop()` is guarded on `running`,
which is not set until `start` returns.

**Nothing bounded any of them.** `withCheckedContinuation` does not observe task
cancellation, so `BoundedWait`, a cancelled test, and teardown were all powerless. The
sends matter most: `SSEHub` broadcasts to its clients one at a time *from inside its own
actor*, so one stream whose peer stopped reading — TCP send window full, completion
correctly not firing — holds the hub, and therefore holds every `ViewerServer.stop()`
waiting to `closeAll()` it, forever. That is a wedge whose only frames are the poll loops
of the coordinators that `stop()` never got to cancel: exactly the sample above.

### What was probed rather than assumed

`swift scripts/probe-network-seam.swift`, sandbox off — the probe is filed so these
figures can be re-run:

- `NWConnection.send`'s `.contentProcessed` completion **does** fire when the connection
  is cancelled in flight (`S1`), and **does** fire when `send` is called on an
  already-cancelled connection (`S2`). So the send seam is not unresumable *by
  cancellation* — the brief's lead that it might be is wrong. It is unresumable by a peer
  that simply stops reading, which no code in the viewer could interrupt.
- The 2026-08-30 `NWListener` `EINVAL` gotcha is **root-caused and was mis-documented**:
  a listener started with no `newConnectionHandler` fails with `POSIXErrorCode 22`; set
  the handler first and the identical listener reports `.ready` with a port (`L1` vs
  `L2`, three trials each, interleaved). Nothing to do with loopback, the parameter set,
  SwiftPM, descriptor pressure or load — and it is why `HTTPServer` never suffered it: it
  assigns the handler before starting. The gotcha now carries the cause and the correction
  in full. It was never the wedge either, because `.failed` resumes.

## The fix

`ResumeOnce` (`Sources/WoodcaseViewer/Server/ResumeOnce.swift`) is now the only way this
target awaits a socket. It resumes its continuation exactly once from whichever arrives
first — the callback, a later callback, or a dispatch deadline — taking the continuation
and its fallback together under one lock, so the expiry's side effect runs *only* when the
deadline is what resumed, and is released the instant anything else does. That last part
is not a nicety: the expiry closure holds the connection it would cancel, and the viewer
makes thousands of ordinary writes a run.

`HTTPServer.outcome(of:)` (`HTTPServer+Startup.swift`) classifies every listener state
with no `default`, so no reachable state can resume nothing again. `.waiting` is reported
as a failure with a remedy naming `--port`, on the reasoning that loopback has no network
path to wait for. A listener that reports nothing at all throws `.unresponsive`. A write
nobody takes drops the client and says so on stderr — the give-up is otherwise silent, and
silence is what made this class of bug cost three wedged hosts across two sessions.

Budgets are 30 s: *not hung* guards, per `project/gotchas.md`, three orders of magnitude
past what binding a loopback port or handing bytes to the transport takes.

## Verification

- Full suite, sandbox off, foreground: **3267 tests passed** (3254 before; +13 new), 39 s.
- `swiftformat . --lint` clean.
- Loaded soak after the fix, on the final tree: `--load 6 --timeout 280` **8/8 reached
  their summary** (65–138 s a run, across three invocations) and `--load 2 --timeout 180`
  **3/3** (48–49 s). Before the fix the same `--load 6` invocation wedged 1 run in 2.
  Fifteen post-fix runs in all, counting four on an intermediate build: **none wedged, no
  `TIMEOUT`, no `NO-SUMMARY`.**
- No `gave up on` line appeared in any post-fix run, so no write ever reached its budget:
  the deadline is a guard that did not fire, not a crutch the suite now leans on.

Three failures across those fifteen runs, none a wedge and none viewer-server-owned: two
runs of the intermediate build hit `PenFileTransactionTests.swift:310` ("locked by another
process; gave up after 10 s" — a wall-clock lock budget losing to `--load 6`, the failure
mode `project/gotchas.md` already names, absent at `--load 2`), and one `--load 2` run hit
`ViewerBrowserTests.selectionScrollsTheOutlineToItsRow`, the known baseline flake.

Run times at `--load 6` spread from 65 s to 142 s with no trend attributable to this
change; nothing here is a performance measurement, and the machine was not quiet enough
for one to mean anything.

## What is proven and what is not

**Proven:** `.waiting` resumed nothing and now cannot; none of the three awaits was
bounded and all three now are; a callback that never fires produces a value within its
budget (`ResumeOnceTests`); the wedge reproduces at `--load 6` and did not recur in six
runs after the fix.

**Not proven:** that the wedge *observed* was one of these three awaits and not a fourth
thing elsewhere. It cannot be proven from a sample, because the suspended task has no
stack — that is the whole difficulty. What can be said is that before this change these
were the only awaits in the process with no budget at all, every other wait in the viewer
and its tests being bounded at 30–60 s, and the run that wedged sat past 280 s. Fifteen
clean loaded runs is evidence, not proof. If the wedge returns, the stderr line and the typed
errors mean the next reader gets a name instead of an empty sample — and if it returns
with *neither*, the seam is exonerated and the search moves on, which is worth as much.
