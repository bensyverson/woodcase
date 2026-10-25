# Document Sessions

One funnel for every edit to a document, and a ledger of who wrote what.

## Overview

A ``DocumentSession`` owns a document while it is open: the ``EditableDocument``, its
``CRDTDocument`` in collaborative mode, the ``Author`` editing it, a ledger of who last
wrote each piece of it, and the document as its file last held it. Every change enters
through one method, ``DocumentSession/submit(_:)``, and comes back as one
``CommittedChange``.

```swift
let session = DocumentSession(
    document: try PenParser.parse(data),
    author: Author(name: "ben", peerID: .generate()),
    file: url,
    collaborative: false
)
let change = try session.submit(.local(LocalEdit(operations: [move])))
```

### The funnel

A change can come from four places — the local author, the file on disk, a collaborator,
or the author's own undo and redo — and each is a ``SessionOrigin``. Whatever the
origin, the owner reacts to the same value:

| Field | What the owner does with it |
| --- | --- |
| ``CommittedChange/invalidation`` | Re-derives layout and rendering for the ``ChangeInvalidation/nodes`` it names, or everything when ``ChangeInvalidation/full`` |
| ``CommittedChange/activity`` | Appends the events to the activity log |
| ``CommittedChange/broadcast`` | Sends the operations to collaborators |
| ``CommittedChange/isDirtying`` | Marks the document edited |
| ``CommittedChange/isUndoable`` | Offers Undo |
| ``CommittedChange/undoEffect`` | Mirrors the undo and redo stacks into its own undo manager |
| ``CommittedChange/kept`` | Tells the author whose work an undo kept |
| ``CommittedChange/conflicts`` | Tells the author where a file merge kept their value over the file's |

So there is no second path that edits the document and forgets to log, broadcast or
invalidate. Each ``AppliedOperation`` carries the operation as applied — normalized to
per-path ``EditOperation/setProperties(_:)`` where a whole-struct write changed only some
paths, and with deep metadata keys folded onto the node's metadata
(``EditOperation/normalized(in:)``) — and its complete inverse, as guarded steps
(``EditableDocument/granularInverse(of:)``).

A ``LocalEdit`` may write one metadata entry by its deep key —
`common.metadata.woodcase.tint` — or a Woodcase-owned key by its natural path —
`kind.spans` — and the session folds it onto the node's metadata
exactly as the CLI's batch planner does (``NodePropertyCodec/folding(_:onto:)``), so an
editor never rewrites the object to change one entry. A metadata write is keyed, undone
and replicated per entry it changes, so it merges with other authors' writes to sibling
entries and an undo keeps theirs (<doc:PenMetadataNamespace>).

The invalidation names what only the document *before* the change knows, which the
document's own cache bookkeeping does not: the parent a node was moved or deleted out
of, every node of a deleted subtree, and every node a detach inserts.

A ``LocalEdit`` lands whole or not at all. Its ``LocalEdit/expecting`` revisions are
checked before anything is applied; if an operation part-way through fails, the ones
before it are undone and the session is left exactly as it was — no sequence number,
no ledger stamp, no activity. In collaborative mode that includes the CRDT: a refused
edit was never broadcast, so its CRDT state is restored rather than unwound, and no
peer ever has to hear of it.

### File merges

When the file changes on disk — another tool, an agent, a `git checkout` — the owner
parses it and submits ``SessionOrigin/file(_:author:)``, naming the writer when the
activity log explains the write. The session needs a ``DocumentMerger`` for this,
given at creation; the library's is `.threeWay` (``ThreeWayMerger``, which is
``DocumentMerge`` behind the seam). Without one the submission throws
``SessionError/mergeUnavailable``; a session that never knew what its file holds — one
wrapping a document with no file state — throws ``SessionError/fileStateUnknown``.

```swift
let session = DocumentSession(document: parsed, author: ben, file: url, merger: .threeWay)
let change = try session.submit(.file(try PenParser.parse(contentsOf: url), author: claude))
for conflict in change.conflicts { /* "Kept your fill; claude also changed it" */ }
```

The merge is three-way: base is the document as the file was last known to hold it
(from creation, the last ``DocumentSession/noteSynced(_:through:)``, or the last file
merge), ours the live document, theirs the file's. Every external change comes in and
every unwritten local change survives; where both changed the same key the local value
wins and the merge reports it in ``CommittedChange/conflicts``. The operations go
through the same path as a local edit — guarded inverses, invalidation, the CRDT in
collaborative mode, so collaborators who cannot see the file receive them — with these
differences:

- the change, and every ledger stamp it makes, belongs to the file's writer, or to
  ``Author/external`` when nobody claimed the write, so the local author's undo keeps it;
- it joins no undo history and leaves redo and the open undo group alone;
- it writes no activity: the writer logged it;
- the file's document becomes the new merge base, and the session is in sync with its
  file again unless local work survived (``MergeResult/keepsLocalChanges``), in which
  case the change is dirtying.

A merge lands whole or not at all, like a local edit; a failed one leaves the base
where it was.

### Remote operations

A collaborator's CRDT operations arrive as ``SessionOrigin/remote(_:from:)`` to a
collaborative session (any other throws ``SessionError/notCollaborative``). Each one the
CRDT accepts stamps the ledger with the keys it wrote — keyed as finely as a local edit,
so a remote write to one override key meets a local undo of that key — under the author
of the replica that made it. Each operation names its replica by ``PeerID``;
``DocumentSession/noteJoined(_:)`` maps a peer to an ``Author``, the sender of a
submission is introduced automatically, and a replica nobody introduced is
``Author/unattributed(peer:)``. A write the CRDT rejects as stale stamps nothing, and a
submission with nothing accepted applies nothing and keeps the current sequence.

The invalidation compares the document before and after the whole batch, because the
reconciliation that ends it may move nodes without naming them: written nodes, moved
nodes with both parents, reordered children lists, the root order and any document
member. Both read only what the batch wrote: every write — each mutation's, and the
reconciliation's own — is noted, as it was, in a `FlatStoreJournal`, the
reconciliation settles only the nodes and lists the journal names
(``EditableDocument/reconcileChildrenWithParents(after:)``), and the comparison reads
only the journal's entries. A collaborator's one-property change therefore costs its
spine, not the document: about 0.14 ms on Penumbra's 2,464-node perf board, flat across
500 changes (release, `WoodcaseBench remote-apply-cost`). Scoping is exact while the flat store
agrees with the CRDT; a local edit that leaves it disagreeing (an index the CRDT's lists
cannot give, a node created again under a tombstoned id) marks the store, and the next
batch reconciles the whole document once, which is when the store always caught up.

A remote change is someone else's work: it is neither undoable nor dirtying, writes no
activity (its author's own session logs it), broadcasts nothing, and leaves the local
author's redo stack and open undo group alone. The local author's later undo keeps it,
as *Keep theirs* below describes. Operations are delivered causally and exactly once: one
whose causal past has not arrived is held — the batch that brings it applies both, in
order, and credits each to its own author — and one already applied is ignored. See
*Causal Delivery* in <doc:CRDTArchitecture>.

### Saving from an app

An app saves through ``PenFileTransaction/save(_:changes:to:log:timeout:)``, which
writes a ``DocumentSnapshot`` under the file's lock in the CLI's bytes and logs the
changes' rows under the session's author (see <doc:WoodcaseActivityLog>). The file may
be a bare `.pen` or a `.umbra` bundle — the save writes the bundle's `document.pen` and
appends to the author's own file in the bundle's shared `history/`, `<author>@<device>.jsonl`
(<doc:PenBundles>); prefer a bundle. The device is the log's ``ActivityLog/device`` —
this Mac's computer name unless the app names one. The save
touches only values, so it runs off the main actor. Around it, the app keeps this
contract:

1. **Keep the unsaved changes.** Append every ``CommittedChange`` the session returns —
   local, undo, redo, file merges; only local, undo and redo carry rows — to a list, and
   drop those with a ``CommittedChange/sequence`` at most a saved snapshot's once its
   save is synced. A debounced save passes the whole list; the save logs only what the
   snapshot includes.
2. **Snapshot, save, report back.** Take ``DocumentSession/snapshot()`` on the session's
   actor, save it in a task, and on an outcome that ``PenFileTransaction/SaveOutcome/isSynced``
   call ``DocumentSession/noteSynced(_:)`` with that snapshot. Changes made while the save
   ran stay unsaved, and the next save checks against what this one wrote
   (``DocumentSession/syncedRevision``, carried as ``DocumentSnapshot/syncedRevision``).
   Two saves can overlap — a debounced save begun while an explicit one still writes —
   and both carry the older synced revision; the later one finds the file holding its
   own snapshot and reports ``PenFileTransaction/SaveOutcome/unchanged``, not a file
   change, so the app never merges its own save back in.
3. **Merge when told.** On ``PenFileTransaction/SaveOutcome/fileChanged(found:lineage:)``
   someone wrote the file since the last sync and nothing was written. Submit
   ``SessionOrigin/file(_:author:)`` with `found` and the lineage's
   ``LogLineage/writer``, append that change to the unsaved list, then save again. If
   local work survived the merge, the save appends a `merge` row so the log still
   explains the file.

```swift
let snapshot = session.snapshot()
switch try await PenFileTransaction.save(snapshot, changes: unsaved, to: url) {
case .wrote, .unchanged:
    session.noteSynced(snapshot)
    unsaved.removeAll { $0.sequence <= snapshot.sequence }
case let .fileChanged(found, lineage):
    unsaved.append(try session.submit(.file(found, author: lineage.writer)))
    // save again
}
```
4. **Never write the file another way.** Every byte goes through the save, or the
   check and the log stop meaning anything; the old direct write of compact JSON is
   gone.
5. **Let the presenter feed merges, not reloads.** An `NSFilePresenter` change
   notification parses the file and submits ``SessionOrigin/file(_:author:)`` (the
   writer from ``LogLineage/read(_:at:from:)``'s ``LogLineage/writer``), unless the
   file holds the session's own last save (its revision is
   ``DocumentSession/syncedRevision``), which is the app hearing itself. The save is a
   plain locked write — the library is cross-platform and uses no `NSFileCoordinator` —
   so an app that coordinates wraps the call in a coordinated write naming its own
   presenter. Either way the check in step 3 is the backstop: a notification that
   arrives late, or not at all, cannot make a save overwrite an agent's write.

#### Folding a run of changes before it goes out

An editor that commits every keystroke — so its own view is always the document — would
log one row per keystroke. It can fold a run first: ``CommittedChange/folding(_:)``
turns consecutive changes of one origin by one author into one change whose
``CommittedChange/activity`` is one row per kind of edit on the same nodes
(``ActivityEvent/folding(_:)``). A typed word becomes one row whose inverse restores the
text before it and whose forward writes the text after; a property write that a later
write of the same keys covers is dropped from both, and structural operations are kept
whole. The folded change carries the run's last ``CommittedChange/sequence`` and
``CommittedChange/documentRevision``, so replacing the run with it in the unsaved list
saves the same snapshot with fewer rows, and the `merge` row still appears when a file
merge follows. Folding touches only the values the app holds: the session's undo
history is unchanged, and `woodcase undo` takes the folded row back as one step. Fold
only what goes out together — Penumbra folds a typing step at its boundary — and never
across a file merge or a collaborator's change, which ``CommittedChange/folding(_:)``
refuses.

#### When the document moves

``DocumentSession/retarget(to:)`` points a session at its document's new file and keeps
everything else: the undo and redo stacks, the ledger, the sequence, the synced revision
and the merge base. Call it instead of rebuilding the session whenever the app's document
gets a new URL — the first save of an untitled document, Save As, Rename, Move To, a move
in the Finder, a renamed bundle. It does no I/O. What follows:

- **First save, Save As.** Create the file through
  ``PenFileTransaction/create(at:document:identity:log:effect:)`` with the snapshot's
  document and the author's name — so its history starts with a `new` row — then
  retarget, then ``DocumentSession/noteSynced(_:)`` with that snapshot. Edits made while
  the document was untitled wrote no rows (a session without a file records none); the
  `new` row's revision explains the file. They stay undoable, and an undo of one after
  the save is logged like any other.
- **A move or rename.** Retarget only: the bytes did not change, so the synced revision
  and merge base stand. The next save resolves its log from the new URL.
- **The log.** A bundle's log moves with the bundle, and its rows keep answering for the
  document under its new name, so `woodcase undo` reaches back across the rename. A bare
  `.pen` files rows by path: after a move its new rows start in the log of wherever it
  now sits — another repository's, or its new folder's — and the rows written before
  stay under the old path in the old log. Crossing log roots or not, the new path's
  history starts with the first save after the move; an agent's `woodcase undo` there
  stops at that point, while the app's own undo stack is unaffected.
- **Unsaved changes** made before the move are logged under the new file when saved:
  the save names the file it writes in every row it appends.

```swift
// The document moved, or an untitled one was just created at `url`.
session.retarget(to: url)
```

### Isolation

A session is a `final class` confined to whoever owns it: the main actor in an app, the
one thread of a CLI verb. It is deliberately not `Sendable`, and ``DocumentSession/submit(_:)``
is synchronous. Background work — saving, exporting, rendering off the main actor —
takes a ``DocumentSnapshot`` from ``DocumentSession/snapshot()``, which is a value, and
reports a save back with ``DocumentSession/noteSynced(_:through:)``.

### The ledger

An undo has to know whether anyone else has changed what it is about to put back. A
revision cannot say: ``EditableDocument/revision(of:)`` is a content hash, with no order,
and a value changed and changed back hashes the same as before.

So every change takes the next ``CommittedChange/sequence`` number, and the session
stamps each ``ChangeKey`` the change wrote — one property path of one node, one
override key, a node's placement, a node's existence — with its author and that number.
"Has someone else written this since my edit?" is then a comparison of two numbers and
two authors.

An author is a name and a ``PeerID``, so the same person in two windows is two authors:
each window's undo keeps the other window's work.

### Undo and redo

The session keeps its own author's undo and redo stacks. Each local edit joins them
as its ``LocalEdit/undoGroup`` says: ``UndoGroup/new`` pushes an entry of its own,
``UndoGroup/coalesce(_:)`` joins the most recent entry while it was opened with the
same key — a drag's hundred moves undo as one — and ``UndoGroup/none`` joins nothing.
Any new local edit clears redo; an undo or a redo closes the open group.

``SessionOrigin/undo`` and ``SessionOrigin/redo`` are changes like any other: they
take the next sequence, stamp the ledger, go through the CRDT and into the activity
log (an undo's events are labeled ``ActivityEvent/Kind/undo``, a redo's ``ActivityEvent/Kind/redo``), and come back as one
``CommittedChange``. What an undo applied becomes the redo entry, and the reverse.
``DocumentSession/canUndo`` and ``DocumentSession/canRedo`` say whether either has
anything to do; with nothing, the change applies nothing and keeps the current
sequence.

### Mirroring the stacks

An app whose menus and shortcuts belong to a platform undo manager (`NSUndoManager`)
mirrors the session's stacks into it rather than keeping a second history. Every
``CommittedChange`` says what it did to them in ``CommittedChange/undoEffect``, so the
mirror acts on the flags instead of inferring them:

| Change | ``CommittedChange/undoEffect`` | The mirror… |
| --- | --- | --- |
| A ``UndoGroup/new`` edit, or the first of a ``UndoGroup/coalesce(_:)`` group | ``CommittedChange/UndoEffect/openedEntry`` | registers an undo action |
| A later edit of the open coalescing group | ``CommittedChange/UndoEffect/joinedEntry`` | registers nothing: one action still undoes the whole drag |
| A ``UndoGroup/none`` edit | — | registers nothing |
| Any of those, when redo held entries | adds ``CommittedChange/UndoEffect/clearedRedo`` | drops its redo actions — for a ``UndoGroup/none`` edit it registers nothing, so the platform manager will not clear them itself |
| An undo or a redo that applied something | ``CommittedChange/UndoEffect/consumedEntry`` and ``CommittedChange/UndoEffect/filedReversal`` | registers the opposite action from inside the one being performed |
| An undo or a redo whose every step was kept | ``CommittedChange/UndoEffect/consumedEntry`` only | registers no opposite action: the entry is gone and nothing replaces it |
| Nothing to undo or redo, an edit that applied nothing, a collaborator's change, a file merge | empty | does nothing |

### Keep theirs

Undo is per author and keeps everyone else's work. When the local author undoes, or
redoes, an entry, each step is weighed against the ledger: only a write by another
author *after* the entry's first change can stop it.

- A property or override key another author has written since is left as they wrote
  it, and reported in ``CommittedChange/kept``. The author's other keys are undone.
- A step that removes or rebuilds a subtree — un-inserting a node, undoing a detach or
  a replace — is skipped when anyone else has since written anything inside it, and
  their writes are reported. Undoing a detach someone has edited inside leaves the
  instance detached.
- A node moved back is left where another author has since moved it; a node put back
  by undoing a delete stays deleted when its parent has since been deleted, or one of
  its ids taken.
- The steps that take back one structural operation run together or not at all, so
  half a detach is never undone.
- A node put back by a move or a delete lands next to the sibling it sat after
  (``Placement``), not at an index someone else's insert has since shifted.

Everything else is undone. The app can then say "Kept 1 change by claude" instead of
silently overwriting it. A whole undo lands or none of it does, like a local edit.

### Rolling back a run of changes

A caller that submits several changes as one unit — a batch line, a CLI verb — takes a
checkpoint first and rolls back to it if the unit fails. The rollback reverts the
document, the ledger, the journaled activity and the undo and redo stacks together, and
in collaborative mode returns the operations collaborators need to follow it.

A rollback never crosses a collaborator's change: if a remote change was journaled after
the checkpoint, ``SessionError/rollbackAcrossRemoteChange`` refuses it and the session
is left as it was. Restoring the ledger would drop that change's stamps while its effects
stay in the document, so a later undo could overwrite it. A remote change also leaves the
open coalescing group open, so a local drag interrupted by a collaborator's edit still
undoes as one step; keep-theirs protects the remote values when it does.

### The CLI on the funnel

The `woodcase` CLI writes through a session too. ``PenFileTransaction`` hands its body an
``ActivityRecorder`` that holds a transient, non-collaborative session over the body's
document, under the `--as` name, with one batch id for the whole transaction. Every
recorder write — and every edit ``BatchApplier`` makes, logged or not — is a
``SessionOrigin/local(_:)`` submission; a failed batch line is a checkpoint and a
rollback; `woodcase undo` replays a logged inverse as a local edit labeled `undo`. So the
log's rows carry the session's granular, complete inverses and the operation as the
writer submitted it in `forward`.

A transient session costs no copy of the document: it keeps the file's document as the
transaction parsed it and builds the editable merge base only if a file merge asks for
it, which a CLI verb never does. Writes the batch grammar has no verb for — removing a
variable, a theme axis or an import alias — go through
``BatchApplier/applyEdit(_:to:recorder:)``, so `woodcase vars rm` and a script's
`doc.vars.rm` use the same funnel.

## Topics

### Sessions

- ``DocumentSession``
- ``DocumentSnapshot``
- ``Author``
- ``SessionError``

### Merging the file

- ``DocumentMerger``
- ``ThreeWayMerger``

### Submitting changes

- ``SessionOrigin``
- ``LocalEdit``
- ``UndoGroup``

### Describing changes

- ``CommittedChange``
- ``CommittedChange/UndoEffect``
- ``CommittedChange/folding(_:)``
- ``AppliedOperation``
- ``ChangeInvalidation``
- ``KeptChange``

### Keys and inverses

- ``ChangeKey``
- ``GuardedInverse``
- ``Placement``
