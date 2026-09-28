# A follow is a value, and a sample cannot see the thing that is stuck

2026-08-31. Two findings from leaf 8kAHL, one about `ActivityReader.follow` and one
about how a wedged `swift test` run is read. The second corrects the premise of the
leaf itself, so it comes first.

## The premise this leaf was filed on is wrong

> **Correction to the issue's own reading.** 8kAHL says: "the only live Woodcase frames
> were two `ActivityReader.follow` poll loops — an await-forever in some activity/follow
> test". The observation is right and the inference does not follow. A Swift task
> suspended at an `await` has **no thread and no stack frames**. `sample` reports thread
> stacks, so in a run wedged on an unresumed continuation or a feed that never yields,
> the wedged code is *invisible by construction* and the only Woodcase frames the sample
> can possibly contain belong to whatever is still running. A poll loop is exactly the
> kind of thing that is still running. Reading it as the culprit sends the next reader
> into the wrong subsystem, which is what happened here.

This was confirmed by direct observation rather than argument. On 2026-08-31, with
several agents building and testing at once, two test hosts were wedged simultaneously:

| pid | checkout | elapsed at 0 % CPU | Woodcase frames |
|---|---|---|---|
| 46108 | main checkout, unmodified `main` | 11 min | two `ActivityReader.follow` poll loops, `ActivityReader.swift:201` and `:107-109` |
| 58566 | a sibling agent's worktree, `follow` not yet rewritten | 10 min | `ActivityReader.follow` at `ActivityReader.swift:201` **and `:208`** — the leaf's two line numbers exactly |
| 48269 | this worktree, `follow` already rewritten | 8 min | **none**, with a live `com.apple.network.connections` queue |

Three hosts, one afternoon. The two carrying the old `AsyncStream`-backed `follow` show
the leaf's signature; the one carrying the rewrite shows no frames of ours at all — and
across ten loaded runs of the rewrite (`scripts/soak-tests 5 … --load 2`, twice) not one
wedged, every run finishing in 41–59 s.

Reproduce: `ps -Ao pid,ppid,etime,pcpu,args | grep swiftpm-testing-helper` to find a host
at 0 % CPU, then `sample <pid> 3 -f <file>` (sandbox off) and read the `Physical
footprint` line first, per `project/2026-08-30-suite-stability.md`.

The first row is a byte-for-byte reproduction of the sample the leaf was filed on — so
the wedge is real, reproducible under multi-agent load, and not rare. The second row is
the same wedge with the follow loops removed: **still 0 % CPU, still stuck, no frames at
all.** The follow loops were bystanders. Whatever is stuck is suspended, and the live
`com.apple.network.connections` queue points at the viewer's Network.framework HTTP seam
(`HTTPServer`, `HTTPConnection`, both of which await `withCheckedContinuation` on a
state handler) rather than at anything in `Sources/Woodcase/Files/`.

**So: the third face of a hang in this suite is 0 % CPU with no frames from our code at
all.** `project/2026-08-30-suite-stability.md` names two — 100 % CPU on one core (the
`ancestors(of:)` cyclic walk, out-of-memory killed) and 0 % CPU with every cooperative
thread in `CTFontCreateWithFontDescriptor` (the font-registry storm). This one has no
signature to read, which is precisely its signature.

## Why `follow` was rewritten anyway

The bystander was worth fixing on its own terms. `ActivityReader.follow` returned an
`AsyncStream` whose producer was an unstructured `Task` created inside the stream's
builder closure. Its lifetime was therefore governed by object-graph reachability —
`onTermination` firing when the stream is dropped or its consumer cancelled — rather
than by structured concurrency. Three ordinary situations leave that poll loop running
for the life of the process:

1. a feed made and never iterated;
2. a consumer torn down by fire-and-forget cleanup that has not run yet — the suite uses
   `defer { Task { await bench.stop() } }` in about thirty places, which is a *request*
   to stop, not a stop;
3. a consumer suspended forever inside its own loop body. This is the expensive one: the
   producer neither knows nor cares that its reader has stopped reading, so it keeps
   polling and keeps buffering (`AsyncStream`'s default policy is `.unbounded`) behind a
   consumer that will never take another event. That is the exact pairing the leaf's
   sample shows — running producers, invisible consumer.

`ActivityReader.Follow` is now a value. It holds no task and starts no work; the polling
*is* the consuming task. It exists exactly as long as somebody is asking for events, it
ends the moment that task is cancelled, and it cannot run ahead of a consumer that has
stopped consuming — the log file, not a buffer in memory, holds what a slow reader has
not reached. There is nothing left to leak.

The red test is `ActivityReaderTests.followIsAValueNotARunningTask`: iterate one feed,
take an event, break, then iterate the same feed again. Against the old implementation
the second iteration **never returns** — an `AsyncStream` is consumable once, and the
first `break` terminated it — so the test hung for the full 30-second `BoundedWait`
budget and was reported as an expired job rather than wedging the run. Against a value
it is two independent walks from the same offset.

## Every wait on a feed is now bounded

`Tests/WoodcaseTests/BoundedWait.swift` races a job against a deadline and cancels it.
The budget is 30 s — a *not hung* guard, deliberately nowhere near the interval under
test, because `project/gotchas.md` records a 10 ms sleep taking twelve seconds to resume
under this suite. Never assert on how long a job took; assert on what it produced. The
limit is honest and worth stating: a deadline works by cancelling, so it bounds any job
that honours cancellation and cannot bound one that does not.

## Verification

`scripts/soak-tests 5 <log> --load 2 --timeout 600`, twice, on a machine already running
several agents' builds and suites on top of the two synthetic busy cores. Before the dot
fix below: **3/5**, both failures the dot race. After it: **4/5**, 3139 tests per run,
41–53 s per run, the single failure being
`ViewerBrowserTests.selectionScrollsTheOutlineToItsRow` — the pre-existing load-sensitive
flake already in `project/gotchas.md`, viewer-owned and untouched here. Across all ten
loaded runs there was no `TIMEOUT` and no `NO-SUMMARY`: nothing wedged.

## What is still open

The wedge itself. It survives this change, it reproduces under multi-agent load, and the
only thread-level evidence points at the viewer's Network.framework HTTP seam — which is
also where `project/gotchas.md` already records an un-root-caused `NWListener` `EINVAL`
in this suite. That is a viewer-surface investigation and was left to its owner.

## A wait that assumed timely scheduling, and the dot it lost

`ViewerFollowBrowserTests.unreadDotUntilViewed` failed two of five runs of the loaded
soak, always at the same step, and it is worth writing down because the failure mode is
invisible from the assertion that fails.

An unread dot lives in the *browser's* `localStorage`, written by `ViewerScript`'s
`change` handler when the event arrives over the stream — never in the markup the server
sends, because the map and the strip are re-rendered on every change. The test's last
step wrote a node, navigated straight to the map, and then waited up to 30 s for the map
to show a dot:

```swift
try await bench.write("Lbl01", to: "Elsewhere", as: "bob")
_ = try await bench.host.load(bench.url("/files/\(bench.fileID)"))   // no wait
await bench.waitFor("the map to dot the artboard that changed", …)
```

If the `change` event had not reached the page before the navigation, the handler never
ran, the mark was never written, and **no amount of waiting on the map could recover it**
— the state the map reads was never created. So a generous 30 s bound bought nothing:
the race was already lost, and the wait only decided how long the suite took to say so.
The same test's *earlier* step gets this right, waiting for the dot on the current page
before moving on; the last step simply omitted it.

The fix is one wait, on the precondition rather than the consequence: block until this
browser has actually recorded the mark, then navigate.

```swift
await bench.waitFor(
    "the write to be marked unread before the page navigates away",
    "return localStorage.getItem('woodcase.unread:\(bench.fileID):Cmp01') === '1';"
)
```

The general shape, which is the point: **bound a wait on the state a later step consumes,
not on the thing you hope that state produces.** A wait placed after an irreversible step
— a navigation, a teardown, a page swap — cannot test what happened before it, and reads
as flakiness in whatever it does assert.
