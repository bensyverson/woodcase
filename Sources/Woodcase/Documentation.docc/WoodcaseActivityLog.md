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
place that does. A **`.umbra` bundle** keeps its own log, at
`<bundle>/.woodcase/activity.jsonl`, before any rule below is asked — see *Bundles* below.
For a bare .pen file:

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

### Bundles

A bundle's log is inside the bundle (``ActivityLog/Origin/bundle(root:repository:)``),
wherever the bundle sits and whatever `$WOODCASE_HOME` says, so the history travels with
the document — that is what a bundle is for. Every row in it is about the bundle's one
document, so a reader asking about that document takes every row, whatever path it was
written under (``ActivityLog/Origin/holdsOneDocument``): a renamed bundle keeps its
history, and `woodcase undo` reaches back across the rename. Rows name a bundle by its
`document.pen` (``ActivityEvent/canonicalPath(for:)``), whichever path the caller gave.
See <doc:PenBundles>.

A **bare file that moves** — a rename, or a move to another repository — keeps nothing:
rows are filed by path, so the new path's history starts with its next write, in the log
of wherever it now sits, and the old rows stay under the old path in the old log.
``DocumentSession/retarget(to:)`` follows a move in an app; see <doc:Session>.

### The `.gitignore` line

The log is generated local state, so the write that *creates* `.woodcase/` inside a
repository adds `.woodcase/` to that repository's root `.gitignore` at the same moment,
creating the file if there is none (``RepositoryIgnoreFile``). Only a missing pattern is
appended — `.woodcase`, `/.woodcase` and `.woodcase/` all count as present — so it happens
once. A bundle inside a repository adds the same line on its own log's first write.
Outside a repository nothing is written, and a `.gitignore` that cannot be written
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
{"batch":"7C6E…","file":"/Users/ana/Designs/dashboard.pen",
 "forward":[{"updateCommon":{"_0":{"nodeID":"jSUCH","common":{"name":"Title"}}}}],
 "identity":"ana",
 "inverse":[{"setProperties":{"_0":{"nodeID":"jSUCH","properties":{"common.name":"child-1"}}}}],
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
- **`op`** — a short verb: `set`, `place`, `add`, `replace`, `cp`, `mv`, `rm`, `override`,
  `detach`, `var`, `import`, `theme`, `undo`, `redo`, `external`, `migrate`, `new`, `merge`. Coarser than ``EditOperation`` on purpose — a feed wants
  "something was set here", not which of the four property operations did it. Two kinds
  look alike and are not: **`mv` is a reparent or a reorder** — the node changed parent or
  index, what `woodcase mv` does — and **`place` is a change of position**: a write of
  `common.x`, `common.y` or both and nothing else, a nudge or a freeform drag
  (``ActivityEvent/Kind/placementPaths``). A write that changes anything beside the
  position, rotation and size included, is `set`; `place` has no verb of its own, and
  `woodcase set x=… y=…` both writes and repeats it. Most kinds are
  derived from the operation; `cp`, `undo` and `redo` are supplied by the caller, because an
  inverse operation looks like any other and only its author knows it is an undo or a
  redo (a ``DocumentSession`` labels its redo rows `redo`; `woodcase undo` treats one as
  an ordinary edit it can take back), and
  `external`, `migrate`, `new` and `merge` are not operations at all — see *Writes from
  outside*, *Rewrites and creations* and *Saves from an app* below.
- **`nodes`** — the node ids the operation touched, subject first, then the parent whose
  children changed. Empty for an operation on the document itself — a variable, an
  import, a theme axis, the root's own properties.
- **`paths`** — the same nodes' name paths, in the same order. Each is read from the
  state where the node exists: after the operation for a node that survived it, before
  it for one the operation removed. So a rename records the new name and a delete records
  the name that was deleted.
- **`inverse`** — the operations that undo this one, in the order they must be applied.
  This is what makes the log an undo source rather than a diary. Every write reaches the
  file through a ``DocumentSession`` — the CLI's transaction holds a transient one — so
  the inverse is the session's, from ``EditableDocument/granularInverse(of:)``: granular
  and complete.
  - **Granular.** A property write undoes as one `setProperties` per path it changed,
    restoring that path's old value: a whole-struct `updateCommon` or same-case
    `updateKind` that renamed a node logs `setProperties {"common.name": old}`, not the
    whole old struct. An override write undoes as one `overrideDescendant` or
    `overrideRoot` per key — writing the old value back, or unsetting a key the write
    added. A step that puts a node back (the move back of a move, the re-insert of a
    delete) carries the index it was captured at.
  - **Complete.** A `detach` row's inverse deletes the expanded subtree and re-inserts
    the ref, because a detach's ids are derived from the document and known before it
    runs. So `woodcase rm --detach` followed by `woodcase undo` restores the file byte for
    byte.

  Before 2026-10-04 inverses were whole-struct snapshots from
  ``EditableDocument/prepareInverse(of:)`` — one `updateCommon` for any rename, the whole
  override entry for any override — and a `detach` row carried only the re-insert. Those
  rows still decode and replay; an old detach row replays as far as it goes. Nothing else
  about a row changed when the CLI moved onto the session: the file's bytes, `op`,
  `nodes`, `paths`, `forward`, `revision` and `batch` are what they were, and
  `external`, `migrate` and `new` rows — which apply nothing — are untouched, as is a
  `--dry-run`, which still appends nothing. The one visible consequence of granularity
  is that an `undo` of a row with several inverse steps writes one `undo` row per step.
- **`forward`** — the operation as applied, exactly as its writer passed it (a
  whole-struct `updateCommon` stays whole), so a reader can show the new values beside
  the old ones in `inverse` without reconstructing them from a later state. One
  operation per row today; an `undo` row's `forward` is the inverse it replayed. Omitted
  when empty: `external`, `migrate` and `new` rows apply nothing, and a line written
  before the field existed (2026-10-04) decodes with an empty `forward`.
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

## Saves from an app

An editor that keeps a document open writes the same rows a CLI verb does.
``PenFileTransaction/save(_:changes:to:log:timeout:)`` takes a ``DocumentSnapshot`` of the
app's ``DocumentSession`` and the ``CommittedChange``s it has not saved yet, locks the
file, writes the CLI's bytes, and appends each change's ``CommittedChange/activity`` —
one row per operation, under the session's author (`ben`), with node ids, granular
inverses and the forward operation. So an agent reading the log sees who changed what,
the next CLI write finds the log explaining the file instead of recording an `external`
row, and `woodcase undo --as ben` steps back through the app's edits like anyone else's.

Before it writes, the save checks under the lock that the file still holds what the
session last synced; if an agent wrote it since, nothing is written and the app merges
the file (``SessionOrigin/file(_:author:)``) before saving again. If the file holds
what the session expected but the log does not explain it, an `external` row goes first,
exactly as a transaction records one. See <doc:Session> under "Saving from an app".

### The merge row

The rows a save appends carry the revisions their changes had *in the session*. When the
session also took in work that writes no rows of its own — a file merge that kept unsaved
local work, a collaborator's operations — after its last logged change, no single
writer's row explains the saved revision. So the save appends one more row, last:

```json
{"batch":"…","file":"/Users/ben/Designs/banking.pen","forward":[…],"identity":"ben",
 "inverse":[{"setProperties":{"nodeID":"Ttl01","properties":{"common.name":"Title"}}}],
 "nodes":["Ttl01"],"op":"merge","paths":["Screen/Title"],"revision":"77a0c2e1",…}
```

- **identity** — the saving identity: the session folded the work in, though somebody
  else wrote it (their own rows, earlier in the log, say who).
- **revision** — the saved revision, so ``LogLineage`` finds the file explained and the
  next write records no `external` row.
- **nodes** and **paths** — every node the folded-in work touched, named as saved.
- **forward** — the folded-in operations as the session applied them.
- **inverse** — the operations that take the folded-in work back out of the saved
  document, when the session can build them: a file merge's operations are the
  session's own, so their inverses are complete. A collaborator's arrive as CRDT
  operations with none, so a row folding any of them carries no inverse.

`undo` never replays a `merge` row and is never stopped by it, whoever saved it. It is a
barrier of a different kind: the session's rows below it were written against a document
without the folded-in work, so their revisions no longer match the file. When the row has
an inverse and the file is in the state it recorded, `undo` replays that inverse on a
scratch copy and judges the rows below against the copy — exactly, as it judges any row —
while applying their inverses to the real document. So `undo --as ben` takes back ben's
own edits and leaves the merged-in values in place. A row whose undo would reach the
folded-in work — its node is, or holds, one the merge touched — is refused as stale
rather than taking that work with it. Without an inverse, or once the file has moved on
from the row's state, the rows below are judged against the file as usual.

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

Both calls read the live `activity.jsonl` only, never the archives rotation moved aside:
on a long history they see its newest part. ``ActivityReader/read(after:file:identity:)``
from ``ActivityCursor/start`` reads every archive and then the live file.

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

Two consequences worth relying on. Canceling the consuming task ends the iteration, and
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
rotation.

A follower that must not lose a single event across a rotation holds an
``ActivityCursor`` instead of a bare offset. The cursor adds the file's inode, which a
rename keeps, so ``ActivityReader/read(after:file:identity:)`` can find the archive the
cursor was taken in, read the rest of it, then every later archive and the live log from
zero — no gap, no repeat. Only when the archive has been deleted does the reader fall back
to restarting from the live log, and then it says ``ActivityReader/Page/restarted``.
``ActivityReader/Follow/Iterator/cursor`` is that position after each event, and the string
form (`<inode-hex>-<offset>`) is what a stored cursor looks like.

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

## Views live beside the log

A read verb — `tree`, `get`, `find`, `shot`, `render` — run with an identity (`--as`, or
`$WOODCASE_AS`) records what it read: one ``ViewEvent`` with the reader, the document,
the verb, the document revision it read and the node ids it printed (at most 64, with
`covered` counting the rest), and whether it covered those nodes alone or their
subtrees. A read with no identity records nothing.

```json
{"covered":1,"file":"/Users/agent/Designs/demo.pen","identity":"claude",
 "nodes":["jSUCH"],"revision":"3f2a91c0d4e5b678","scope":"nodes",
 "time":"2026-10-04T16:31:04.123Z","verb":"get"}
```

Views go to `views.jsonl` in the same directory (``ViewLog``), **never** to
`activity.jsonl`. This log is the write history, and three things read it on the
assumption that every row is a write: ``LogLineage`` takes the newest row as the file's
last known state, the undo walk treats a foreign row as a later edit, and change
attribution pairs rows with file changes. A view in this file would break all three.
`views.jsonl` shares the lock discipline and rotation (`views.<timestamp>.jsonl`, its own
8 MB threshold) and is read with ``ViewReader``, through the same ``ActivityCursor``.

Two rules keep it small and harmless. A view the reader's newest view of the same file
already covers — same revision, no new node, no wider scope — is not written
(``ViewEvent/covers(_:)``). And recording is best effort: it happens after the read,
outside the .pen file's lock, and a views file that cannot be written leaves the verb's
output and exit status untouched.

## Following one document

``PenFileFollower`` is the library's answer to "tell me what happens to this file": an
`AsyncSequence` that watches the document (``FileWatcher``), reads both logs from their
cursors, and pairs each file change with the rows that explain it (``ChangeMatcher``).

```swift
var presence = PresenceTracker()
for await event in PenFileFollower(file: url) {      // a .pen or a .umbra
    presence.record(event)
    switch event {
    case let .changed(change): refresh(change.nodes, by: change.identities)
    case let .viewed(view): showCursor(view.identity, on: view.nodes)
    case .activity, .restarted: break
    }
}
```

Like ``ActivityReader/Follow`` it is a value with no task of its own: canceling the
consuming task stops and releases the watcher. Where it begins is a
``PenFileFollower/Start``:

- ``PenFileFollower/Start/end`` — only what happens next. It is resolved when the
  follower is made, so a write that lands before iteration begins is still seen.
- ``PenFileFollower/Start/beginning`` — every retained row as history
  (``PenFileFollower/Event/activity(_:)``), then every read, then what happens next.
- ``PenFileFollower/Start/since(_:)`` — the rows and reads stamped at or after a moment,
  as `.beginning` delivers them, then what happens next as `.end` delivers it. "Who was
  here in the last ten minutes" costs the ten minutes, not the history: each log is walked
  backward from its end, and an archive is opened only when the window reaches past the
  live file's first row. The history ends where the logs ended when the follower was
  made, so a write after that arrives live, matched to its change, and the seam loses and
  repeats nothing. The walk runs when iteration begins (``PenFileFollower/makeAsyncIterator()``),
  not when the follower is made.
- ``PenFileFollower/Start/position(_:)`` — just after the last event an earlier
  iterator took: ``PenFileFollower/Iterator/position`` resumes a later follower without
  gaps.

A delete-then-recreate write keeps the file followed, because the watcher watches the
document's folder as well as the file; where that folder cannot be opened — a sandboxed
app holding a grant on one bare `.pen` — the follower polls the file instead. A
``PresenceTracker`` folds the follower's events into who changed and who viewed which
nodes last.

## Topics

### Following

- ``PenFileFollower``
- ``PresenceTracker``

### Views

- ``ViewEvent``
- ``ViewLog``
- ``ViewReader``

### Writing

- ``ActivityRecorder``
- ``ActivityLog``
- ``PenFileTransaction/save(_:changes:to:log:timeout:)``

### Reading

- ``ActivityReader``
- ``ActivityEvent``

### Undoing

- ``ActivityUndo``
- ``UndoStep``
- ``UndoUnit``
- ``LogLineage``
