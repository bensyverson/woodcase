# CRDT Architecture

Convergent data types that enable real-time collaborative editing of .pen documents.

## Overview

Woodcase's sync layer uses Conflict-free Replicated Data Types (CRDTs) to enable
multiple peers to edit the same document concurrently without a central server. Each
peer maintains a local ``CRDTDocument`` alongside its ``EditableDocument``. The CRDT
layer translates local edits into replicable operations and merges remote operations
into the local state — guaranteeing that all peers converge to the same document,
regardless of operation order or network topology.

### Architecture at a Glance

```
Local edit → EditableDocument.applyLocal(_:)
           → validate — refuses here, before anything is logged
           → CRDTDocument.processLocal(operation:document:)
           → [CRDTOperation]  ← send to peers

Remote op  → EditableDocument.applyRemote(_:)
           → CRDTDocument.processRemote(operation:document:)
           → [DocumentMutation] → applied to flat store
```

The ``EditableDocument`` flat store remains the materialized view that your app
observes and renders. The ``CRDTDocument`` is a shadow structure that owns all
convergence metadata.

### Clock Primitives

Every operation receives a unique ``Timestamp`` composed of a ``LamportClock``
counter and a ``PeerID``. The Lamport clock ensures causal ordering: each peer
increments its clock on every local operation and merges the maximum on every
remote operation. When two timestamps have the same counter, the ``PeerID``
breaks the tie deterministically.

A ``VectorClock`` tracks per-peer progress and is attached to each operation as
a causal dependency set. This lets receivers detect missing operations and request
retransmission.

### LWW Registers and Property Maps

Scalar properties (name, opacity, width, fill color) use Last-Writer-Wins (LWW)
semantics via ``LWWRegister``. Each register stores a value and the ``Timestamp``
of the write that produced it. A later write wins; ties are broken by peer ID.

``LWWPropertyMap`` groups per-node registers into a single map keyed by property
path (e.g. `"common.name"`, `"kind.width"`). When a remote `setProperty` operation
arrives, the map compares timestamps and either accepts or discards the update.

A node's ``PenExtras`` — the keys its file carried that the model does not claim — are
one more register in the same map, under the reserved path
``CRDTDocument/extrasProperty`` (`"extras"`), holding the whole set. They arrive with the
node in its `createNode`; after that a local write is either a replace, which gives the
node its replacement's extras, or a `setProperties` naming `extras.<key>` paths, which
replicates as one write of the patched register — never key by key, because a per-key
write racing a whole-register one would leave peers disagreeing on which won. The
register's path has no `common.`/`kind.` prefix, so no edit verb can name it.

The register is per node, so two peers editing *different* extras of one node
concurrently keep only the later peer's set. Extras are rarely edited at all — a three-way
merge or an undo is the only writer — so per-key registers are not worth a second
granularity the replacement path would have to reconcile with.

A node's `common.metadata` goes the other way: it replicates **per entry**, and never as
the whole object. Each top-level key is a register, and so is each key under the
Woodcase namespace (`common.metadata.type`, `common.metadata.woodcase.tint`); a local
metadata change — a `set` folds to a whole-object write — is sent as one write per entry
that changed (``NodePropertyCodec/metadataEntryWrites(from:to:)``), so two peers changing
one note's tint and its state both keep their edit, and no whole-object write exists to
race an entry write. See <doc:PenMetadataNamespace>.

A local `setProperties` is resolved, and its writes emitted, in one order on every peer:
broadest storage first, ties by path (``EditOperation/SetProperties/orderedProperties``;
<doc:EditingDocuments> has the rule). Its keys can share storage — `common.metadata`
beside `note.fontSize` — so the patch's own dictionary order, which is hash order seeded
per process, would let two peers resolve one patch to different nodes. A replica receiving
the writes holds no map to order: each `setProperty` names one path, carries the value the
sender resolved, and is applied in the order the log delivers it.

### RGA Lists

Child ordering within a parent uses a Replicated Growable Array (``RGAList``).
Each element is assigned a ``PositionID`` (derived from its insertion timestamp)
that is stable across replicas. Deletions are tombstones — the entry is marked
deleted but retained so that concurrent inserts relative to that position still
resolve correctly.

When two peers insert after the same predecessor concurrently, the entry with
the higher ``PositionID`` appears first (leftmost), producing deterministic
interleaving on all replicas.

Moves within or between lists are handled atomically: a single
``CRDTOperation/Payload/listMove(_:)`` tombstones the entry in the source list
and inserts it in the target list, carrying both the original ``PositionID``
(for lookup) and a new position timestamp (for ordering at the destination).

### Kleppmann Tree Move

Structural reparenting — moving a node from one parent to another — uses the
Kleppmann tree move algorithm via ``TreeMoveCRDT``. Each move operation records
the node, the new parent, and a timestamp. The CRDT maintains a total-ordered
log of all moves and replays the log to compute the current parent map.

Cycle detection is built in: if applying a move would create a cycle in the tree
(e.g. moving a parent under its own descendant), the move is silently rejected
during replay. Because all replicas process the same log, they all reject the
same moves and converge on the same acyclic tree.

**Acyclic is a property of the settled tree, not of every instant.**
``EditableDocument/applyRemote(_:)`` applies a batch one operation at a time, and
each of those mutations projects the replayed move log back onto the flat
``EditableDocument/parents`` map. A batch that ends acyclic — three peers each
moving one of A, B, C under the next — passes through a state that is not, and
every observer that runs *inside* that window sees it. The expansion cache's
invalidation rule is one such observer: it walks the parent chain in a `defer` on
every mutation. So any walk over `parents` must terminate on a chain that does not
end; ``EditableDocument/ancestors(of:)`` and ``EditableDocument/isDescendant(_:of:)``
stop at the first id they have already seen. A walk that trusted the chain grew an
array until the process was killed for it, with no summary and no crash report —
see `project/2026-08-30-suite-stability.md`.

### Operation Log and Sync Protocol

The ``OperationLog`` is an append-only log of ``CRDTOperation`` values. Each
operation carries a ``Timestamp`` (unique ID), a ``VectorClock`` (causal
dependencies), and a ``CRDTOperation/Payload`` (the mutation).

The consuming app owns persistence and transport. The sync API is intentionally
minimal:

- **Local path:** Call ``EditableDocument/applyLocal(_:)`` with an ``EditOperation``.
  This updates the flat store, generates ``CRDTOperation``s, and returns them for
  the app to send to peers. It fails closed: the operation is checked against the
  same guards ``EditableDocument/apply(_:)`` enforces *before* `processLocal` sees
  it, because `CRDTDocument` mutates eagerly — an operation it has processed is
  already in the log and on its way to the peers. A refused edit throws the same
  ``EditingError`` it would outside collaborative mode, and leaves the log,
  the tombstones and the flat store exactly as they were.
  Two operations have no CRDT primitive of their own and are decomposed before
  replication: ``EditOperation/detachRef(_:)``, which is planned once — its ids are
  derived (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``), namespaced by this
  peer's id so a concurrent detach of the same instance elsewhere creates distinct nodes,
  and avoiding the replica's tombstones as well as its live ids — and split into a delete
  and an insert, and
  ``EditOperation/replaceSubtree(_:)``, which becomes the deletes, property writes and
  inserts that add up to it. Both are validated as a whole first, so the decomposition
  cannot be refused half way through.
  One operation is **local-only**: ``EditOperation/setDocumentProperties(_:)`` — the
  root's `fonts`, `version`, `fileToken` and extras — has no replicated register, so it
  is validated, applied to the flat store, and replicates nothing. Peers can therefore
  disagree on those keys until each takes the same write some other way, such as merging
  the same file.
- **Remote path:** Call `applyRemote(_:)` on ``EditableDocument`` with operations
  received from a peer. This feeds them through the CRDT layer and applies the
  resulting ``DocumentMutation``s to the flat store.
- **Catch-up:** Call `pendingOperations(since:)` on ``EditableDocument`` with a peer's
  vector clock to get the operations they haven't seen.

### Snapshots and State Transfer

A ``CRDTSnapshot`` captures the complete CRDT state as a `Sendable` value type.
This enables the "Hot Swap" scenario: a peer joins a live session and initializes
from another peer's current state rather than replaying the entire operation history.

A snapshot and a ``CRDTOperation`` are the *only* things that travel between peers. A
``CRDTDocument``, like the ``EditableDocument`` it shadows, is not `Sendable`: each peer's
document stays in the isolation domain that owns it, and convergence happens by exchanging
values. See *Who owns a document* in <doc:EditingDocuments>.

```swift
// Sender: capture and serialize current state
let snapshot = crdtDocument.snapshot()
let data = try JSONEncoder().encode(snapshot)

// Receiver: join from snapshot + current document
let snapshot = try JSONDecoder().decode(CRDTSnapshot.self, from: data)
let editable = EditableDocument(from: currentPenDoc, snapshot: snapshot, peerID: myPeerID)

// Replay any offline operations the new peer had queued
editable.replayOfflineOperations(offlineOps)
```

The snapshot's Lamport clock is automatically advanced during initialization so
the new peer's timestamps don't collide with those in the snapshot.

### Checkpoints and Log Truncation

Over time the operation log grows unbounded. Checkpoints provide a coordination
mechanism for truncation: each peer broadcasts its ``VectorClock`` via
``EditableDocument/checkpoint()``, the app computes the consensus clock using
``VectorClock/minimum(of:)``, and all peers truncate acknowledged operations
with ``EditableDocument/truncateLog(acknowledgedBy:)``.

Woodcase provides the clock and truncation primitives. The consuming app owns
peer discovery, checkpoint exchange, and consensus computation.

> Important: Truncation reclaims the **operation log only**. The convergence
> metadata — ``TreeMoveCRDT``'s move log, RGA tombstones, and the LWW property
> maps — is never pruned by anything; it grows for the life of the document.
> Consensus also requires a complete peer set for ``VectorClock/minimum(of:)``,
> so a deployment with open-ended peer identities never reaches a consensus
> clock and never truncates. (Recorded during the 2026-08-31 CRDT-routing
> spike; see the note on job leaf `aPPZS`.)

### DocumentMutation

``DocumentMutation`` is the bridge between the CRDT layer and the flat store.
After processing a remote operation, ``CRDTDocument`` returns mutations like
`.setChildren`, `.setProperty`, `.createNode`, and `.deleteNode` that the
``EditableDocument`` applies to update its observable state.

A batch of remote operations ends with a reconciliation, because the list CRDTs may
hold an order the tree move CRDT disagrees with. The whole-document pass,
``EditableDocument/reconcileChildrenWithParents()``, is its definition; a batch runs
``EditableDocument/reconcileChildrenWithParents(after:)`` instead, which settles only
the nodes and lists the batch's `FlatStoreJournal` names — every write a mutation made,
noted before it landed — and agrees with the whole pass on every key while the flat
store agreed with the CRDT before the batch. `RemoteReconcileFuzzTests` holds the two to
each other after every batch of random concurrent edits.

## Topics

### Clock Primitives

- ``LamportClock``
- ``Timestamp``
- ``VectorClock``
- ``PeerID``

### Conflict Resolution

- ``LWWRegister``
- ``LWWPropertyMap``
- ``RGAList``
- ``PositionID``
- ``TreeMoveCRDT``

### Replication

- ``CRDTDocument``
- ``CRDTOperation``
- ``OperationLog``
- ``DocumentMutation``
- ``PropertyDiff``

### State Transfer

- ``CRDTSnapshot``
