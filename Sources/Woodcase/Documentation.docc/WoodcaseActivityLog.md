# The Activity Log

An append-only record of every edit Woodcase commits: what changed, who changed it, and
how to change it back.

## Overview

Every operation a ``PenFileTransaction`` commits is written as one JSON object on one
line of `activity.jsonl`. That file is the history, the feed the viewer tails, and the
source `woodcase undo` replays. It is *derived* state — the .pen files are the truth — so
deleting it costs history, not designs.

The log is written by ``ActivityLog``, read by ``ActivityReader``, and filled by an
``ActivityRecorder`` that a transaction hands to its body.

```swift
try await PenFileTransaction.run(at: url, identity: "ana") { document, recorder in
    try recorder.apply(.updateCommon(rename))
    try recorder.apply(.moveNode(reparent))
}
```

Two operations, two events, one batch id — appended once the file is safely on disk.

## Where it lives

With the project, not with the user. ``ActivityLogLocation`` resolves it, and is the only
place that does; for a given .pen file:

1. **`$WOODCASE_HOME`**, when set and not empty, is the whole answer: one log at
   `$WOODCASE_HOME/activity.jsonl`, whatever file is being edited.
2. Otherwise, the nearest directory **at or above the file's own that holds a `.git`** —
   a directory in a checkout, a file in a worktree — and the log is
   `<that root>/.woodcase/activity.jsonl`.
3. Otherwise there is no project, so the log sits **beside the file**, in
   `<the file's directory>/.woodcase/activity.jsonl`.

```swift
let log = ActivityLogLocation.log(for: url)       // <repo>/.woodcase/activity.jsonl
let here = ActivityLogLocation.log(inDirectory: cwd)
```

A verb that names a file reads and writes that file's log; one that names none — `activity`
with no `--file`, `serve` with no files — reads the working directory's. `serve` over files
from two projects follows both logs at once (``ActivityLogLocation/logs(for:workingDirectory:environment:)``).

There is no home-wide log: a single `~/.woodcase` would answer "what happened here?" with
everything that happened anywhere, and an agent working in a sandbox that permits writes
under the project would find its own history unwritable. This is the same choice a task
tracker's in-repo database makes.

### The `.gitignore` line

The log is generated local state, so the write that *creates* `.woodcase/` inside a
repository adds `.woodcase/` to that repository's root `.gitignore` at the same moment,
creating the file if there is none (``RepositoryIgnoreFile``). Only a missing pattern is
appended — `.woodcase`, `/.woodcase` and `.woodcase/` all count as present — so it happens
once. Outside a repository nothing is written, and a `.gitignore` that cannot be written
is not an error: the edit and its log line are the work.

### Pointing it somewhere else

`WOODCASE_HOME` moves the whole directory, which is what a shared feed or an awkward
sandbox wants. It is the one variable Woodcase reads for a user's own state:
``WoodcaseHome`` resolves it, and the font and image caches — `$WOODCASE_HOME/fonts`
and `$WOODCASE_HOME/images`, `~/.woodcase` when it is unset — follow the same rule. The
log is the exception that has no home-wide default: with nothing set it belongs to the
project, not to the user. A test injects a directory instead:

```swift
let log = ActivityLog(home: temporaryDirectory)   // no environment mutation
```

The directory itself is created on the first append, and an empty batch does not even
do that.

## The wire format

One event per line, JSON with sorted keys and unescaped slashes. Other tools read these
fields by name, so the names and their meanings are a contract, not an implementation
detail. Broken across lines here for reading; on disk it is one line:

```json
{"batch":"7C6E…","file":"/Users/ana/Designs/dashboard.pen","identity":"ana",
 "inverse":[{"updateCommon":{"_0":{"nodeID":"jSUCH","common":{"name":"child-1"}}}}],
 "nodes":["jSUCH"],"op":"set","paths":["layout-vertical/Title"],
 "revision":"3f2a91c0d4e5b678","time":"2026-08-29T16:31:04.123Z"}
```

- **`time`** — when the operation was applied. ISO-8601, UTC, milliseconds:
  `2026-08-29T16:31:04.123Z`. Held to whole milliseconds so a line decodes back to an
  event equal to the one that wrote it.
- **`identity`** — the writer's name, as passed to `--as` (or `$WOODCASE_AS`). It is a
  plain name, *not* a ``PeerID``: a peer id is a bare UUID with no display name and would
  say nothing to a reader. The CLI maps the same name to a `PeerID` where the CRDT layer
  needs one; the log keeps the readable half.
- **`file`** — the absolute path of the .pen file, standardized with symlinks resolved
  (``ActivityEvent/canonicalPath(for:)``), so `/tmp/x.pen` and `/private/tmp/x.pen`
  produce one string and a filter on either finds both.
- **`op`** — a short verb: `set`, `add`, `replace`, `cp`, `mv`, `rm`, `override`,
  `detach`, `var`, `import`, `theme`, `undo`, `external`, `migrate`, `new`. Coarser than ``EditOperation`` on purpose — a feed wants
  "something was set here", not which of the three property operations did it. Most are
  derived from the operation; `cp` and `undo` are supplied by the caller, because an
  inverse operation looks like any other and only its author knows it is an undo, and
  `external`, `migrate` and `new` are not operations at all — see *Writes from outside*
  and *Rewrites and creations* below.
- **`nodes`** — the node ids the operation touched, subject first, then the parent whose
  children changed. Empty for an operation on the document itself — a variable, an
  import, a theme axis.
- **`paths`** — the same nodes' name paths, in the same order. Each is read from the
  state where the node exists: after the operation for a node that survived it, before
  it for one the operation removed. So a rename records the new name and a delete records
  the name that was deleted.
- **`inverse`** — the operations that undo this one, from
  ``EditableDocument/prepareInverse(of:)``, in the order they must be applied. This is
  what makes the log an undo source rather than a diary.
- **`revision`** — the document's ``EditableDocument/documentRevision`` *after* this
  operation. Per operation, not per transaction, so `undo` can check one event against
  the file's current revision and refuse rather than guess.
- **`batch`** — an id shared by every event of one transaction. Absent from an event
  that stands alone, which today means an `external` row. It is what `undo` reads to
  reverse a whole command in one step — see *Undo is by transaction* below.

## Writes from outside

The log's whole claim is that it accounts for the file. A `revision` is the document's
content hash *after* its operation, so **the newest event's revision equals the file's
revision** exactly when woodcase wrote the file last and nothing has touched it since.
``LogLineage`` is that comparison, and it is asked twice: by every logged transaction as
it opens the file, and by `undo` of every event it walks back through.

When it fails, somebody rewrote the file without asking for the lock — another editor
saving, a script with a JSON parser. The write says so on standard output and carries on:

```text
note  banking.pen was rewritten outside woodcase since rev 9c1b04e6 (ana, 10:32); the log has no record of that change
```

A note and not a refusal: the outside edit may be perfectly legitimate, and refusing
would strand a real document. The transaction then records what it found, as the first
event of its own append:

```json
{"file":"/Users/ana/Designs/banking.pen","identity":"","inverse":[],"nodes":[],
 "op":"external","paths":[],"revision":"5404f4d0","time":"2026-09-07T10:33:12.004Z"}
```

It names nobody, touches no node, and carries no inverse, because woodcase did not do it
and cannot undo it. Its `revision` is the revision the file was **found** at. That row is
what makes the note fire once rather than on every subsequent write: after it, the newest
event's revision is the file's revision again and the invariant holds.

A file with **no** history is not a divergence — a fresh checkout or an exported design
makes no claim either way — so the first write to a file is never noted.

Two consequences worth knowing. `woodcase activity` shows the row, so the hole in the
history is visible where the history is read. And `undo` stops at it, refusing rather
than guessing past an edit it has no inverse for:

```text
Cannot undo …/banking.pen: cannot undo past an edit made outside woodcase at 10:33 …
[exit 3]
```

## Rewrites and creations

Two writes change a .pen file without editing a document, and both go through the file's
lock and leave a row, so the log accounts for every byte woodcase writes:

- **`migrate`** — `woodcase migrate` rewrote the file in the current format
  (``PenFileTransaction/migrate(at:identity:log:timeout:effect:rewritingCurrent:diagnostics:)``).
  A migration happens as a file is *read*, so the document was already migrated before
  the rewrite: the row's `revision` is the one the file had and still has, and it carries
  no inverse. `undo` passes over it — whoever wrote it — because every edit before it is
  still exact against the document.
- **`new`** — `woodcase new` created the file
  (``PenFileTransaction/create(at:document:identity:log:effect:)``), under a lock taken
  before the file appears at its path. It is the file's first row, and `undo` stops
  there: nothing before it is this file's history.

Both carry the writer's `--as`, or name nobody, like any other write.

## Undo is by transaction

Every event of one command shares a `batch` id, and `undo` reverses **one transaction per
step**: a batch of forty lines, a `cp --times 3` or a script run goes back with one
`undo`, and `-n` counts commands rather than rows. `--event` is the finer step, one
logged row at a time.

The walk is one event at a time either way — each row is judged on its own revision, so
each inverse is exact — and what a transaction changes is only whether the next row
counts against `-n`. That is what lets the two units compose: after an `--event` undo has
taken the last row of a command, a plain `undo` finishes the rest of that command as one
step. ``ActivityUndo`` is the walk, and ``UndoStep`` the rule it makes each decision with.

## Two processes, no torn lines

An append takes an exclusive `flock(2)` on the log file — the same lock a transaction
takes on a .pen file — and writes the whole batch in one pass at the end of the file.
Concurrent `woodcase` processes therefore produce whole, separate lines.

Readers take no lock at all. ``ActivityReader`` stops at the last newline in the file, so
a line a writer is halfway through is simply not consumed yet and the next read picks it
up complete. Following the log costs the editing process nothing.

## Resuming

A reader works in byte offsets, not event counts:

```swift
let reader = ActivityReader()
var page = try reader.read(file: url)
render(page.events)

// later, on the next poll
page = try reader.read(from: page.nextOffset, file: url)
```

``ActivityReader/Page/nextOffset`` is the byte just past the last **complete** line, and
counts lines that were filtered out as well as those returned — so a follower watching
one file still advances past everybody else's events. ``ActivityReader/tail(count:file:identity:)``
gives the last N events, and ``ActivityReader/follow(from:file:identity:pollInterval:)``
polls and yields them as they arrive.

## Following is the consumer's own loop

``ActivityReader/Follow`` is a **value**, not a running task. It holds nothing and starts
nothing; the polling happens inside whichever task is calling `next()`, which is what
makes a leaked follower impossible to have. A feed with its own producer task begins
polling when it is made and stops only when something reaches back to cancel it, so a
feed nobody iterates, a consumer torn down by cleanup that has not run yet, or a consumer
suspended forever in its own loop body all leave a poll loop running for the life of the
process — and the last of those keeps the producer reading and buffering behind a reader
that will never take another event.

Two consequences worth relying on. Cancelling the consuming task ends the iteration, and
that is the *only* ending: a quiet log is a log with nothing to say yet, never a feed that
has finished, so a caller wanting a bounded wait imposes one itself. And a `Follow`
iterated twice is two independent walks from the same offset, because the cursor lives in
the iterator and the log file — not a buffer in memory — is what holds events a slow
consumer has not reached.

A line that cannot be decoded — a scrap from a crash, or a field a newer version wrote —
is stepped over and counted in ``ActivityReader/Page/skippedLines`` rather than stopping
the reader forever at the same byte.

## Rotation

Before an append, a log at or past ``ActivityLog/rotationThreshold`` (8 MB) is renamed to
`activity.20260829T163104Z.jsonl` beside itself and a fresh file takes its place. The
rename happens under the lock, so only one process rotates a given file, and the new file
is created immediately.

A follower notices because the file it resumes into is *shorter* than the offset it held:
the reader starts again from zero and sets ``ActivityReader/Page/restarted``, which a feed
should read as "the history before this point has moved to an archive", not as new
activity. The heuristic only fails if a fresh log grows past the old offset between two
polls — megabytes within one poll interval — so a follower that keeps up never misses a
rotation. Nothing reads the archives; they are there for the operator, not the tool.

## Nothing written, nothing logged

Events are appended **after** the .pen file is committed. A transaction whose body throws
and one whose edits cancel out both append nothing, because neither changed the file.
Operations applied straight to the document rather than through the recorder are also
unlogged — the one way to make an edit the transaction cannot account for, and there is
no reason to want that.

## The unattributed writer

An identity is *not* one of the reasons an edit goes unlogged. A write with no `--as` and
no `$WOODCASE_AS` is recorded exactly like any other, under ``ActivityEvent/unattributed``
— the empty name. That is the whole point of the log: `woodcase serve`, `activity
--follow`, the viewer's unread marks and `undo` read this file and nothing else, so a
write that left no line here would be invisible to every one of them while still changing
the document and bumping its revision. An unattributed write is a real state and readers
already render it — the viewer draws a `?` disc titled "unattributed".

Because the empty name is a name, a filter matches it the way it matches any other: `--as
ana` never returns unattributed events, and following `ana` never moves for them.

## Topics

### Writing

- ``ActivityRecorder``
- ``ActivityLog``

### Reading

- ``ActivityReader``
- ``ActivityEvent``

### Undoing

- ``ActivityUndo``
- ``UndoStep``
- ``UndoUnit``
- ``LogLineage``
