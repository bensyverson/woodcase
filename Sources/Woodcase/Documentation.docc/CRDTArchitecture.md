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

A ``VectorClock`` tracks per-peer progress: its entry for a peer is the Lamport time of
the latest of that peer's operations this replica has applied. Each operation carries
the clock as it stood before the operation — its ``CRDTOperation/dependencies``, its
causal past — which is what causal delivery waits on. Because entries are Lamport times,
a clock answers for an operation id directly (``VectorClock/covers(_:)``), which is the
comparison the multiplayer relay makes with the op ids it can see.

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

An instance's overrides replicate **per key** too. Each key of a descendant's override
is its own register under `kind.descendants.<descendant>.<key>`, and each root-override
key under `kind.rootOverrides.<key>`, segments escaped as metadata entry keys are. An
override can hold JSON `null` (it clears that key on the instance), so a present value
travels wrapped as `{"value": …}` and `null` means the key is gone; a descendant left with
no keys, and an emptied map, are removed. Every local write of the maps — an override, a
root override, an `updateKind`, or a `setProperties` naming `kind.descendants` or
`kind.rootOverrides` — is sent as the entries it changed, never as a whole map, so two
people overriding different keys of one instance both keep theirs
(`CRDTOverrideKeyTests`). A raw ``EditOperation/OverrideRoot`` naming a Woodcase-owned key
(`kind.strokeDash`, `common.locked`) is stored on the ref's own `metadata.woodcase`, not
among its root overrides, so it replicates as those metadata entries, sorted by path,
followed by the root-override entries for the rest.

**Text content is last-writer-wins per node.** A text node's content is one register, so
two people typing in the same text node at once keep only the later one's text. That is
acceptable for now: a character-level text CRDT is a larger piece of work than any
current need.

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
  ``EditOperation/setDocumentProperties(_:)`` — the root's `fonts`, `version`,
  `fileToken`, table declarations and root extras — replicates one
  ``CRDTOperation/SetDocumentProperty`` per key it changes, each its own last-writer-wins
  register (``CRDTDocument/documentPropertyTimestamps``), so two peers writing different
  root extras both keep theirs.
- **Remote path:** Call `applyRemote(_:)` on ``EditableDocument`` — or submit
  ``SessionOrigin/remote(_:from:)`` to a ``DocumentSession`` — with operations received
  from a peer, in any order. They are delivered causally (below), fed through the CRDT
  layer, and the resulting ``DocumentMutation``s applied to the flat store.
- **Catch-up:** Call `pendingOperations(since:)` on ``EditableDocument`` with a peer's
  vector clock to get the operations they haven't seen.

### Causal Delivery

A relay delivers late, out of order and more than once: a retry, a replay after a
reconnect, a joiner's snapshot that already holds some of what follows. The merges above
are order-free only for operations whose causal past has been applied — a write to a node
not yet created would be dropped, and an insert after a list position not yet known would
land at the end of the list, on one replica and not another; an insert applied twice
would appear twice. So Woodcase delivers causally and exactly once, in the replica
(``CRDTDocument``), for both ``EditableDocument``'s `applyRemote(_:)` and a
``DocumentSession``:

- An operation the clock already ``VectorClock/covers(_:)`` — applied before — or one
  already held is ignored.
- An operation whose ``CRDTOperation/dependencies`` the clock does not
  ``VectorClock/dominates(_:)`` is held (``CRDTDocument/heldOperations``); the Lamport
  clock witnesses it at once, so no local operation made meanwhile takes its id.
- Every held operation whose causal past has arrived is then applied, smallest id first,
  until none is ready — so the batch that brings a missing operation applies everything
  it was holding up.

Because each peer's operations are applied in the order it made them, the clock entry
for a peer says exactly which of its operations are here. A replica's own operations
replayed from an earlier run (*Offline replay*, below) are held like anyone's, and a
local operation made while some are held depends on them, so peers keep the replica's
order. `CRDTCausalDeliveryTests` covers the rules, and `SessionShuffledDeliveryFuzzTests`
— the relay contract — runs two sessions editing over several rounds while a network
delivers a random part of what is in flight, shuffled and partly twice; they converge on
every seed.

``CRDTDocument/processRemote(operation:document:)`` remains the raw step: it applies one
operation as given, without waiting or deduplicating.

Held operations are not replica state: a snapshot does not carry them, and there is no
bound on how many a replica holds — a peer that sends operations whose causal past never
arrives grows the hold. The relay only stores and forwards operations it accepted from
an authenticated peer.

### Remote Input Is Untrusted

A peer can send any value a field's type allows — through a bug or on purpose — and a
relay replays what it stored to every peer that rejoins, so an operation that crashed one
replica would crash them all, again on every reconnect. Nothing a peer sends may trap or
hang a replica (the multiplayer relay's security review, H5; leaf Ol1s6D).

The clocks are the one place remote values meet arithmetic: witnessing a time sets the
Lamport clock to `max(local, remote) + 1`, which traps on `UInt64.max`, and a merged
vector clock entry for this replica is the base its next local operation increments. So
``CRDTDocument/validateRemote(_:)`` refuses an operation whose own time or any dependency
entry ``LamportClock/admits(_:after:)`` rejects: past ``LamportClock/ceiling``
(2⁵³ − 1, the multiplayer relay's `MaxTime` and the largest integer JSON carries exactly),
or more than ``LamportClock/maximumLead`` (2³²) ahead of the local clock. The relay's own
jump bound is far tighter (10⁶ past the room's high-water time); the replica's is loose
because it judges against its own clock, which may lag the room's while it catches up,
and it must never refuse an operation the relay accepted from an honest peer. It is a
backstop for running without a relay, not a second policy.

A refused operation is not logged, witnessed or applied: the document, the clocks and
the log stay exactly as they were. The refusal is a ``RemoteInputError`` the app reports —
on ``CommittedChange/rejected`` for a ``DocumentSession`` (the rest of the batch still
lands), or returned by `applyRemote(_:)` on a bare ``EditableDocument``. A snapshot is
checked the same way by ``CRDTSnapshot/validate()`` before a replica adopts it: its clock
and vector clock must be under the ceiling, and its tree must hold no parent cycle, which
the next move's cycle check would walk forever.

Everything else a peer sends is safe as given: an unknown id, list or position is a
no-op; a property path or value the codec does not accept leaves the property as it was
(see ``CRDTDocument``'s property codec); a create whose parent the tree refuses — the node
itself or its descendant — places the node at the root rather than closing a parent cycle
in the flat store. Nesting depth is bounded where an operation is decoded: Foundation's
`JSONDecoder` refuses a document nested deeper than 512 levels with an error.
`RemoteOperationFuzzTests` throws hostile operations — extreme times and dependency
entries, junk ids and paths, extreme and deeply nested values, self-parented creates — at
a replica and holds it to that.

### Snapshots and State Transfer

A ``CRDTSnapshot`` captures the complete CRDT state as a `Sendable` value type.
This enables the "Hot Swap" scenario: a peer joins a live session and initializes
from another peer's current state rather than replaying the entire operation history.

A replica is a document *and* the CRDT state that says how it came to be, and the two must
agree. So a joiner takes both from the donor, together, as a ``CRDTStateTransfer`` — the
donor's materialized document and its snapshot, taken at one moment. The joiner's own file
plays no part: it may be older than the session or another file entirely, and a store built
from it would disagree with the donor's CRDT state on every node either changed.

A ``CRDTStateTransfer`` and a ``CRDTOperation`` are the *only* things that travel between
peers. A ``CRDTDocument``, like the ``EditableDocument`` it shadows, is not `Sendable`:
each peer's document stays in the isolation domain that owns it, and convergence happens by
exchanging values. See *Who owns a document* in <doc:EditingDocuments>.

```swift
// Donor: take its document and CRDT state together, and serialize them
let transfer = try #require(editable.stateTransfer())
let data = try JSONEncoder().encode(transfer)

// Joiner: join from the donor's document and state
let received = try JSONDecoder().decode(CRDTStateTransfer.self, from: data)
let joined = try EditableDocument(joining: received, peerID: myPeerID)

// Replay any offline operations the joiner had queued, before editing
joined.replayOfflineOperations(offlineOps)
```

The transfer is validated first (``CRDTStateTransfer/validate()``): its snapshot as
``CRDTSnapshot/validate()`` checks one, and its document must hold no node the snapshot
deleted. The snapshot's log is adopted under the joiner's own peer id, and its Lamport
clock advanced, so the joiner's operations neither carry the donor's id nor collide with
its timestamps. Held operations do not travel: the donor's are still on their way to the
joiner from the relay.

**Offline replay.** A peer that edited while disconnected and rejoins from a donor —
keeping its peer id, which the relay binds — replays its offline operations as it would
take anyone's. Those the donor's state already covers are ignored; the rest are applied
in causal order; and one whose causal past the donor lacks (an operation from a third
peer the joiner saw and the donor has not yet) is held rather than applied against a list
position or node the joiner does not have. Applied, they are in the joiner's log, so
`pendingOperations(since:)` sends them on. Replay every offline operation in one call
before the first local edit: one replayed after a local edit would be taken for a
duplicate.

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
- ``RemoteInputError``

### State Transfer

- ``CRDTSnapshot``
- ``CRDTStateTransfer``
