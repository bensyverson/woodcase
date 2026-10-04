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
| ``CommittedChange/kept`` | Tells the author whose work an undo kept |

So there is no second path that edits the document and forgets to log, broadcast or
invalidate. Each ``AppliedOperation`` carries the operation as applied — normalized to
per-path ``EditOperation/setProperties(_:)`` where a whole-struct write changed only some
paths (``EditOperation/normalized(in:)``) — and its complete inverse, as guarded steps
(``EditableDocument/granularInverse(of:)``).

The invalidation names what only the document *before* the change knows, which the
document's own cache bookkeeping does not: the parent a node was moved or deleted out
of, every node of a deleted subtree, and every node a detach inserts.

A ``LocalEdit`` lands whole or not at all. Its ``LocalEdit/expecting`` revisions are
checked before anything is applied; if an operation part-way through fails, the ones
before it are undone and the session is left exactly as it was — no sequence number,
no ledger stamp, no activity. In collaborative mode that includes the CRDT: a refused
edit was never broadcast, so its CRDT state is restored rather than unwound, and no
peer ever has to hear of it.

Only ``SessionOrigin/local(_:)`` is accepted so far. File merges, remote operations,
undo and redo throw ``SessionError/unsupportedOrigin(_:)`` until their support lands.

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

### Keep theirs

Undo is per author and keeps everyone else's work. This is the contract
``SessionOrigin/undo`` implements once it is accepted; the ledger and the guarded
inverses each ``AppliedOperation`` carries are already in place for it. When the local
author undoes an edit:

- A property or override key another author has written since is left as they wrote
  it, and reported in ``CommittedChange/kept``.
- A structural step that would destroy another author's later work — un-inserting a
  node someone has since edited inside — is skipped, its node kept, and reported.
- A node put back by a move or a delete lands next to the sibling it sat after
  (``Placement``), not at an index someone else's insert has since shifted.

Everything else is undone. The app can then say "Kept 1 change by claude" instead of
silently overwriting it.

### Rolling back a run of changes

A caller that submits several changes as one unit — a batch line, a CLI verb — takes a
checkpoint first and rolls back to it if the unit fails. The rollback reverts the
document, the ledger and the journaled activity together, and in collaborative mode
returns the operations collaborators need to follow it.

## Topics

### Sessions

- ``DocumentSession``
- ``DocumentSnapshot``
- ``Author``
- ``SessionError``

### Submitting changes

- ``SessionOrigin``
- ``LocalEdit``
- ``UndoGroup``

### Describing changes

- ``CommittedChange``
- ``AppliedOperation``
- ``ChangeInvalidation``
- ``KeptChange``

### Keys and inverses

- ``ChangeKey``
- ``GuardedInverse``
- ``Placement``
