# The suite's flakes were a runaway, a wedge, an orphan, and three wall clocks

2026-08-30. Leaf `QGISs`. All figures on this Mac (M-series, macOS 26.5.2), quiet
unless the run says otherwise, on `wt/flaker` off `main` at `0158471`.

Four symptoms had been recorded over 2026-08-29/30 and treated as four problems:

1. a full run that **wedges** at ~0 % CPU for 6–27 minutes, sampled once beneath
   CoreText's `fontd` XPC and once beneath WebKit's `IPC::StreamConnectionWorkQueue`;
2. `swift test --filter "WoodcaseTests\."` and `swift test --skip Viewer` **dying
   ~8–10 s in with exit 1**, no `Test run with` summary, no issue, no crash text;
3. `ViewerPagesTests` failing on **loopback timeouts** and on `batch.pen is locked by
   another process; gave up after 5s`;
4. one **orphaned `woodcase activity --follow`** left behind by every run.

They are four problems after all — but not the four they looked like. Symptom 2 is a
40 GB out-of-memory kill from a product bug in the CRDT path; symptom 1 is the whole
cooperative thread pool blocked inside one `fontd` XPC call; symptom 3 is wall-clock
budgets in tests; symptom 4 is a child nobody was answerable for. The runaway made all
of the others look worse than they were, which is why they read as one story for a day.

## 1. The runaway: an unbounded walk over a transiently cyclic parent map

`swift test --filter "WoodcaseTests\."`, sandbox off, reproduced the silent exit-1 on
the first attempt. `sample <pid>` on the helper while it was "hung" — it was not hung,
it was at 100 % CPU on one core — gives the whole answer:

```text
Physical footprint:         33.2G
Physical footprint (peak):  40.2G
...
CRDTConcurrentMoveTests.threeNodeCycleAttempt()      CRDTConcurrentMoveTests.swift:166
  EditableDocument.applyRemote(_:)                   EditableDocument+CRDT.swift:172
    EditableDocument.applyMutation(_:)               EditableDocument+CRDT.swift:350
      EditableDocument.invalidatingExpansions(...)   EditableDocument+ExpansionInvalidation.swift:0
        $defer #1 ...                                EditableDocument+ExpansionInvalidation.swift:40
          EditableDocument.expansionCanDepend(on:)   EditableDocument+ExpansionInvalidation.swift:62
            EditableDocument.ancestors(of:)          EditableDocument+Queries.swift:43
```

(`sample 66314 5 -f QGISs-spin1.txt`, sandbox off, 2026-08-30 01:11.)

`ancestors(of:)` was `while let parent = parents[current]`. `applyRemote` applies a
batch one operation at a time, and `threeNodeCycleAttempt` is three peers moving A
under B, B under C and C under A: the batch's *result* is acyclic, and the test asserts
that, but the batch passes through `fA → fB → fC → fA`. The expansion cache's
invalidation rule walks the parent chain in a `defer` on **every** mutation, so it ran
inside that window, appended to an array forever, and reached 40 GB.

That is the exit-1: the kernel kills the test host on memory pressure. There is no
crash report and no summary because nothing in the process got to write one — the last
line in the log is cut mid-word, which is a block-buffered stdout dying, not a test
failing.

It is **not** the "wedge". That was this document's first reading, and a soak run
disproved it within the hour — see part 2. The runaway does inflate everything around
it (a 40 GB footprint puts the whole machine into swap, which is where the recorded
12-second `Task.sleep`, the loopback timeouts and the 5-second lock timeouts come
from), but the 0 %-CPU hang has a cause of its own.

**Fix:** ``EditableDocument/ancestors(of:)`` and
``EditableDocument/isDescendant(_:of:)`` stop at the first id they have already seen.
Regression test: `Tests/WoodcaseTests/EditableDocumentCycleSafetyTests.swift`. This is
a product bug, not a test bug — `applyRemote` is the multiplayer path, and a real peer
exchange reaches the same state.

## 2. The wedge: the whole cooperative pool inside one `fontd` XPC call

With the runaway fixed, ten full runs passed on a quiet machine. Run 4 of five runs
against two busy cores then hung, and `scripts/soak-tests`'s watchdog sampled it before
killing it — which is the only reason there is anything to read, because a hung run
prints nothing at all (`swift test --quiet` had produced **61 bytes** in five minutes).

The sample says it plainly. Footprint 188 MB, so not the runaway. The main thread idle
in `swift_task_asyncMainDrainQueue`. And **all eight** cooperative threads —
`com.apple.root.default-qos.cooperative`, one per core — in the same place:

```text
PenTextMeasurer.resolveFontUncached(family:size:weight:style:cache:)   (×6)
PenTextMeasurer.fontFamilyAvailable(_:)                                (×2)
  CTFontCreateWithFontDescriptor
    TDescriptorSource::CopyDescriptorsForRequest
      XTCopyFontsWithProperties                       (libFontRegistry)
        -[XTypeXPCClient run:errorHandler:]
          __NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__
            mach_msg2_trap
```

(`scripts/soak-tests 5 <log> --load 2`, 2026-08-30 01:41–01:46; the sample is written
beside the log as `<log>.run4.sample.<pid>`.)

Core Text does not resolve a family name in-process. It sends a **synchronous XPC
message to `fontd`** and blocks the calling thread on the reply, with no timeout and no
cancellation. Swift's cooperative pool has one thread per core; a blocking call
occupies one for as long as it blocks. Eight parallel test cases each rendering text
put all eight threads into that wait at once, the process had nothing left to run, and
it never came back.

**Fix:** ``FontRegistryGate`` — one process-wide recursive lock, held across every call
that reaches the font registry (``PenTextMeasurer/fontFamilyAvailable(_:)``, the
uncached half of ``PenTextMeasurer/resolveFont(family:size:weight:style:)``,
`hasWeightAxis`'s `CTFontCopyVariationAxes`, and `PenIconFontRenderer`'s
`CTFontCreateWithName`). One request is in flight at a time, which is what `fontd`
serves anyway; the pile-up that wedges it never forms. ``FontResolutionCache`` answers
a repeat lookup without reaching the gate, so only *first* resolutions of distinct
families ever contend.

This is what the two retired gotchas were looking at, and what
`ViewerPagesTests`'s `@Suite(.serialized)` comment already guessed at ("a dozen
concurrent font lookups through CoreText's registry daemon, which is where a whole run
has been seen to wedge"). The guess was right; it was just fixed one suite at a time
instead of once in the library.

### The gate widened an existing race, and that is worth recording

`PenTextMeasurerFontCacheTests` asserts exact hit/miss counts on a cache of its own, and
its comment said that a private cache made the accounting immune to other suites. It did
not: ``PenFontRegistry/generation`` is process-wide, a registration by any suite discards
*every* cache, and ``FontResolutionCache/setFont(_:for:resolvedAt:)`` then drops the very
store being counted. The gate made the window wider — a thread queued for the gate is a
thread not yet resolving — and the test reported 2 of 3 once in ten runs.

Two changes, because the premise was wrong on both sides. The generation is now read
*inside* the gate, immediately before the Core Text call, so a registration that landed
while the thread was queued counts as having happened before the resolution it really
did affect. And each case in that suite runs its window again if a registration landed
inside it, which is what makes its count a measurement of the cache rather than of its
neighbors.

## 3. The orphan: `--follow` had no reason to stop

`ActivityCommandTests.followSeesNewEventsPromptly` launched `woodcase activity
--follow` with `Process` and tore it down with `terminate()` + `waitUntilExit()`.
`waitUntilExit()` is unbounded, and a run that is killed never reaches the teardown at
all — so each run left one follower behind, reparented to `launchd`, polling forever.

**Fix, at the source.** `activity --follow` now races its event stream against
``ParentProcessWatch``, which polls `getppid()`: when the launcher dies the kernel
reparents the process, and a parent id that is no longer the recorded one ends the
follow. A follower that was *born* orphaned (`nohup … &`, a launch agent) has no death
to notice and is left alone.

**Fix, in the test.** `ChildProcess` (in `WoodcaseCommandTests`) never calls
`waitUntilExit()`: it polls against a deadline, escalates `SIGTERM` → `SIGKILL`, records
a failure at each escalation, and `SIGKILL`s any survivor in `deinit`.
`ChildProcess.withChild(…)` stops the child however the body ends.

> A process-wide census of surviving children was considered as the "suite-level
> guard" and rejected: swift-testing runs suites in parallel, so a census taken at the
> end of suite A sees suite B's live children and fails an innocent run. The `deinit`
> backstop attributes precisely and cannot race.

## 4. The wall clocks

Three budgets in tests measured the machine rather than the behavior, and all three
are now bounded at "not hung" scale per `project/gotchas.md`:

| where | was | now |
| --- | --- | --- |
| viewer tests' `PenFileTransaction` lock wait | 5 s (product default) | `ViewerFixtures.lockBudget`, 60 s |
| viewer tests' loopback request | 15 s | `ViewerFixtures.requestBudget`, 60 s |
| `PerformanceBudget` under a debug build | hard failure | advisory; fails at 4 × limit |

The viewer's server, the transaction it waits on, and every `EditableDocument` the rest
of the suite builds all queue on the **main actor** — `EditableDocument` is
`@MainActor`, and the performance suites hold it for seconds at a time on 5000-node
documents. A viewer test's lock poll cannot run while that is happening, so a 5-second
budget there is a measurement of the suite's main-actor demand. Serializing the viewer
suites against the heavy library suites was the alternative; swift-testing has no
cross-suite ordering, and a hand-rolled gate would have been a deadlock risk for a
symptom that a generous bound removes outright.

The performance decision is written up in <doc:WoodcasePerformance>: over `limit` is a
printed `BUDGET-ADVISORY` line on a debug build and a failure on a release build or
under `WOODCASE_BUDGET_STRICT=1`; over 4 × `limit` fails either way, because load
inflates a figure but does not change its order of growth.

## What was measured after

`scripts/soak-tests 10 <log>` then `scripts/soak-tests 5 <log> --load 2`, on this
machine, 2026-08-30 02:0x–02:2x. **10/10 and 5/5**, 2647 tests in 269 suites each time,
30.4–31.6 s quiet and 34.3–37.6 s against two busy cores. No `woodcase` child outlived
any run.

The intermediate soaks are the interesting ones, and they are why there are two parts
above rather than one:

| soak | result |
| --- | --- |
| 10 quiet, runaway fixed, no font gate | 10/10 |
| 5 loaded, no font gate | **4/5** — run 4 hung 300 s in `fontd`; the watchdog sampled and killed it |
| 10 quiet, font gate in | **9/10** — one `PenTextMeasurerFontCacheTests` count, the race the gate widened |
| 10 quiet, final | 10/10 |
| 5 loaded, final | 5/5 |

A quiet ten-run soak would have passed the leaf and shipped the wedge. The load is not
decoration.
