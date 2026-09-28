# Phase 2: CRDT Core — Convergence Machinery for Collaborative Editing

## Context

Phase 1 (complete, commit `a40d4b2`) built `EditableDocument` — a mutable flat-store editing model with typed operations and round-trip materialization. It supports single-user editing. Phase 2 adds the CRDT (Conflict-free Replicated Data Type) core so that two `EditableDocument` instances can process the same operations in any order and converge to identical state. This is the foundation for real-time multiplayer editing.

**Full design document:** [`project/2026-04-01-editing-architecture.md`](../../project/2026-04-01-editing-architecture.md) — section 4 covers the CRDT architecture in detail, section 7 has Phase 1 implementation notes with tips for this phase. Read the Phase 1 details block for gotchas.

**No sync protocol, no transport, no persistence** — those are Phase 5. Phase 2 builds the in-memory CRDT state machine and proves convergence. The app controls where/how operations are persisted and exchanged; Woodcase owns the convergence guarantees.

## Background for Implementation

### What Phase 1 built

All files in `Sources/Woodcase/Editing/`:

| File | Purpose |
|------|---------|
| `EditableDocument.swift` | `@MainActor @Observable final class`. Flat store: `nodes: [String: PenNode]`, `children: [String: [String]]`, `parents: [String: String]`, `rootOrder: [String]`, plus `version`, `themes?`, `imports?`, `variables?`. Init flattens a `PenDocument`; `materialize()` reconstructs one. All stored properties are `public internal(set)`. |
| `EditableDocument+Apply.swift` | `apply(_ operation: EditOperation) throws` — dispatches to `applyInsert`, `applyDelete`, `applyMove`. Private helpers: `validateNoDuplicateIDs(in:)`, `flattenAndInsert(_:parentID:)`, `collectDescendants(of:)`. |
| `EditableDocument+Queries.swift` | `node(id:)`, `parentID(of:)`, `childIDs(of:)`, `ancestors(of:)`, `isDescendant(_:of:)`, `allNodeIDs`, `rootNodes` |
| `EditableDocument+Properties.swift` | `applyUpdateCommon`, `applyUpdateKind` (strips children from kind) |
| `EditableDocument+Variables.swift` | add/update/remove variable (sets dict to `nil` when empty) |
| `EditableDocument+Imports.swift` | add/update/remove import |
| `EditableDocument+Themes.swift` | add/update/remove theme axis |
| `EditOperation.swift` | `enum EditOperation: Friendly` — 14 cases, each with a `Friendly`-conforming parameter struct (InsertNode, DeleteNode, MoveNode, UpdateCommon, UpdateKind, AddVariable, etc.) |
| `EditingError.swift` | 12 error cases |
| `PenNode+Editing.swift` | `withEmptyChildren()`, `withChildren(_:)`, `canHaveChildren`, `childIDs` on `PenNode.Kind` |

### Key types

- **`PenNode`** — `let id: String`, `var common: PenNodeCommon`, `var kind: Kind`. Kind has 14 cases; only `.frame` and `.group` have children.
- **`PenNodeCommon`** — 13 properties: name, x, y, rotation, opacity, enabled, flipX, flipY, reusable, theme, context, layoutPosition, metadata
- **`PenVariable`** — `type: PenVariableType` + `value: PenVariableValue` (simple or themed)
- **`Friendly`** — `typealias Friendly = Codable & Equatable & Hashable & Sendable`
- **`PenValue<T>`** — enum: `.literal(T)` or `.variable(String)`. Used for x, y, opacity, etc.
- **`PenSizing`** — enum: `.fixed(Double)`, `.fitContent(fallback:)`, `.fillContainer(fallback:)`, `.variable(String)`
- **`AnyCodable`** — type-erased Codable wrapper (already exists in `Models/AnyCodable.swift`)

### Known issues from Phase 1

1. **`PenNode.Kind` Codable is non-standard.** `Kind.init(from:)` throws unconditionally ("should not be decoded directly"). `EditOperation.UpdateKind` contains a `Kind` field, so encoding/decoding it will fail. Must be fixed before the CRDT op log can serialize operations (Task 0).

2. **`children` map stores entries for empty arrays.** `children[id] == nil` does NOT mean "can't have children." Check `nodes[id]?.kind.canHaveChildren` for the authoritative answer.

3. **Document-level fields are optional.** `variables`, `imports`, `themes` become `nil` (not `[:]`) when empty. This matters for equality checks.

### Reference material for CRDT algorithms

- **Kleppmann tree move:** Paper: "A highly-available move operation for replicated trees" (Kleppmann et al. 2020). TypeScript implementation: [codesandbox/crdt-tree](https://github.com/codesandbox/crdt-tree). Key insight: everything is a `Move(timestamp, parent, metadata, child)` operation. Delete = move to trash sentinel. Cycle prevention at apply time, not generation time. Out-of-order ops trigger undo-redo replay of the move log.
- **RGA (Replicated Growable Array):** Each element has a unique `(counter, peerID)` ID. Insert = "insert after predecessorID". Concurrent inserts at same position ordered by descending ID (newer/higher wins leftmost). Delete = tombstone (mark deleted, keep in structure).
- **LWW Register:** Compare by Lamport timestamp; ties broken by peer ID (lexicographic).

### Project conventions

- Swift 6.2+, macOS 15+ / iOS 18+
- **Strict TDD:** write tests first, verify they fail (RED), then implement (GREEN). If an existing test must change, explain why and get user consent.
- One type per file; extensions in `BaseType+ExtensionName.swift`; folders one level deep max
- All new types conform to `Friendly` where possible
- `swiftformat .` and `swift test --quiet` before committing (pre-commit hooks)
- **Sandbox must be disabled** for `swift build`, `swift test`, `swiftformat`, `mkdir`, and git commands (`dangerouslyDisableSandbox: true`)
- When constructing `PenNode` in tests: `PenNode(id: "x", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData()))` — no `.init()` shorthand
- DocC annotations on all public types/methods with 100% coverage
- Do not modify existing types (`PenDocument`, `PenNode`, etc.) unless absolutely necessary — the editing/sync layers are additive

## Architecture Decision

**The CRDT sits alongside `EditableDocument` as a parallel shadow structure, not inside it.**

`EditableDocument` remains the `@Observable` flat store that SwiftUI observes — plain Swift dictionaries. A new `CRDTDocument` class owns the CRDT metadata (timestamps, RGA structures, tree move log) and provides convergence machinery. `EditableDocument` gains an optional reference to `CRDTDocument` and routes operations through it when in collaborative mode.

**Why not replace the storage?** `@Observable` requires plain stored properties. Wrapping every value in an LWW wrapper would break observation and make materialization indirect. Instead, CRDT metadata is a shadow structure, and the flat store is the "materialized view."

**Two apply paths:**
- `apply()` — unchanged from Phase 1. Single-user, no CRDT overhead.
- `applyLocal()` — routes through `CRDTDocument`, generates `CRDTOperation`s for replication, then updates the flat store.
- `applyRemote()` — applies a `CRDTOperation` from another peer, resolves conflicts via CRDT rules, updates the flat store.

CRDT mode is opt-in: `EditableDocument(from: doc, peerID: myPeerID)`.

**App boundary:** Woodcase owns the CRDT state machine (convergence guarantees). The consuming app owns persistence and transport of operations — it calls `pendingOperations(since:)` to get ops to store/send, and `applyRemote()` to replay ops from storage or network. The app can store serialized `CRDTOperation` values in iCloud, Application Support, SQLite, etc.

### The property granularity bridge

Phase 1's `updateCommon` replaces the entire `PenNodeCommon` struct. The CRDT needs per-property tracking for fine-grained conflict resolution. Solution: a diffing layer computes which fields changed between old and new values, and the CRDT generates one `setProperty` operation per changed field. This preserves Phase 1's coarse API while enabling property-level LWW.

### Conflict resolution rules

| Conflict | Resolution |
|----------|------------|
| Same property, two peers | LWW by Lamport timestamp, ties broken by peer ID |
| Edit vs delete of same node | Delete wins. Edits to tombstoned nodes are silently dropped. |
| Move into deleted parent | Moved node is promoted to root (no data loss) |
| Insert child into deleted parent | New node is inserted at root (no data loss) |
| Concurrent cycle-creating moves | Kleppmann's algorithm rejects the cycle-creating move; both replicas converge regardless of operation order |
| Same node moved by two peers | Last writer (higher timestamp) wins |

## Files to Create

### Source — `Sources/Woodcase/Sync/` (new directory)

| # | File | Contents | ~Lines |
|---|------|----------|--------|
| 1 | `LamportClock.swift` | `struct LamportClock: Friendly, Comparable` — `tick()`, `witness(_:)` | ~30 |
| 2 | `PeerID.swift` | `struct PeerID: Friendly, Comparable` — wraps UUID string, `generate()` | ~20 |
| 3 | `Timestamp.swift` | `struct Timestamp: Friendly, Comparable` — `(time: UInt64, peerID: PeerID)`, total order | ~25 |
| 4 | `VectorClock.swift` | `struct VectorClock: Friendly` — `dominates(_:)`, `merge(_:)`, `increment(for:)` | ~40 |
| 5 | `LWWRegister.swift` | `struct LWWRegister<Value: Friendly>: Friendly` — `set(_:at:) -> Bool` | ~30 |
| 6 | `LWWPropertyMap.swift` | `struct LWWPropertyMap: Friendly` — per-property timestamp tracking for a node | ~40 |
| 7 | `PropertyDiff.swift` | `diffCommon(old:new:) -> Set<String>`, `diffKind(old:new:) -> Set<String>` | ~80 |
| 8 | `RGAList.swift` | `struct RGAList<Element: Friendly>: Friendly` — insert, delete (tombstone), move, `elements` | ~150 |
| 9 | `CRDTOperation.swift` | `struct CRDTOperation: Friendly` with `Payload` enum (setProperty, listInsert, listDelete, treeMove, createNode, deleteNode, set/removeVariable, set/removeImport, set/removeThemeAxis) | ~120 |
| 10 | `OperationLog.swift` | `struct OperationLog: Friendly` — append local/remote, `pending(since:)`, `truncate(acknowledgedBy:)` | ~60 |
| 11 | `TreeMoveCRDT.swift` | Kleppmann's algorithm: `MoveOp`, `parentMap`, `moveLog`, `applyMove(_:) -> Bool`, `rebuild(existingNodes:)` | ~100 |
| 12 | `DocumentMutation.swift` | `enum DocumentMutation` — atomic mutations to apply to EditableDocument's flat store | ~30 |
| 13 | `CRDTDocument.swift` | `@MainActor final class` — owns all CRDT state, `processLocal()`, `processRemote()`, `pendingOperations(since:)` | ~200 |

### Source — `Sources/Woodcase/Editing/` (modifications + additions)

| # | File | Contents |
|---|------|----------|
| 14 | `EditOperation+Codable.swift` (new) | Custom Codable for `EditOperation.UpdateKind` using a `KindEnvelope` wrapper | ~80 |
| 15 | `EditableDocument+CRDT.swift` (new) | `applyLocal(_:) -> [CRDTOperation]`, `applyRemote(_:)`, `applyRemote(_: [CRDTOperation])`, `pendingOperations(since:)`, `applyMutation(_:)` | ~80 |
| 16 | `EditableDocument.swift` (modify) | Add `crdtDocument: CRDTDocument?` property and `init(from:peerID:)` convenience initializer | ~20 added |

### Tests — `Tests/WoodcaseTests/`

| # | File | Tests |
|---|------|-------|
| 17 | `EditOperationCodableTests.swift` | Round-trip encode/decode of every `EditOperation` case, especially `UpdateKind` with frame/text/rectangle/unknown kinds |
| 18 | `LamportClockTests.swift` | tick increments, witness updates to max+1, witness with lower value |
| 19 | `TimestampTests.swift` | Ordering: same time different peers, different times, equal timestamps |
| 20 | `VectorClockTests.swift` | dominates (true/false/concurrent), merge = component-wise max, increment |
| 21 | `LWWRegisterTests.swift` | Higher timestamp wins, stale write rejected, tie-breaking by peerID, convergence |
| 22 | `LWWPropertyMapTests.swift` | Accept newer, reject older, independent properties don't interfere |
| 23 | `PropertyDiffTests.swift` | Common: change name only, change multiple, change none. Kind: change width on frame, different kind cases |
| 24 | `RGAListTests.swift` | Insert at beginning/middle/end, delete (tombstone), concurrent inserts at same position, move within list, convergence, insert after tombstone |
| 25 | `CRDTOperationTests.swift` | Round-trip serialization of every payload case |
| 26 | `OperationLogTests.swift` | appendLocal increments clock, appendRemote advances witness, pending returns correct subset, truncate removes acknowledged ops |
| 27 | `TreeMoveCRDTTests.swift` | Simple move, cycle detection, concurrent cycle-creating moves (both orderings converge), move to root, late-arriving op triggers rebuild |
| 28 | `CRDTDocumentTests.swift` | processLocal produces correct CRDTOperations for each EditOperation type, processRemote applies/rejects correctly |
| 29 | `EditableDocumentCRDTTests.swift` | applyLocal produces ops, plain apply() still works without CRDT, applyRemote updates flat store, applyRemote with stale change is no-op |
| 30 | `CRDTConvergenceTests.swift` | Two peers edit different/same properties, edit vs delete, concurrent list inserts, property-based random convergence |
| 31 | `CRDTConcurrentMoveTests.swift` | Cycle-creating moves, same node moved by two peers, move to deleted parent |
| 32 | `CRDTConcurrentDeleteTests.swift` | Delete vs edit (edit dropped), delete parent vs insert child (child promoted to root), delete vs move into (move target promoted to root) |
| 33 | `CRDTFuzzTests.swift` | Randomized: 2-3 peers, 50-100 ops each, random interleaving, assert convergence |

### Documentation

| # | File |
|---|------|
| 34 | `Sources/Woodcase/Documentation.docc/CRDTArchitecture.md` — DocC article explaining CRDT primitives, local/remote flow, convergence, and how to enable collaborative mode |
| 35 | Update `Sources/Woodcase/Documentation.docc/Woodcase.md` — add Sync section to topics |
| 36 | Update `Sources/Woodcase/Documentation.docc/EditingDocuments.md` — mention CRDT/collaborative mode |
| 37 | Update `README.md` — add doc link if new DocC article added |

## Implementation Order (12 tasks)

### Task 0: Fix EditOperation serialization

**The problem:** `PenNode.Kind.init(from:)` throws unconditionally. `EditOperation.UpdateKind` contains a `Kind` field, so JSON round-tripping fails. The CRDT op log needs to serialize operations.

**Tests first (`EditOperationCodableTests.swift`):**
- Round-trip every `EditOperation` case through `JSONEncoder`/`JSONDecoder`
- Specifically test `UpdateKind` with `.frame`, `.text`, `.rectangle`, `.unknown` kinds
- Verify existing `PenNode` Codable is unaffected

**Implementation (`EditOperation+Codable.swift`):**
Create a `KindEnvelope` wrapper struct that encodes `PenNode.Kind` as `{"type": "frame", ...data...}` — mirroring `PenNode`'s own Codable but standalone. Give `EditOperation.UpdateKind` a custom `init(from:)`/`encode(to:)` that uses `KindEnvelope` for the `kind` field. Do NOT modify `PenNode.Kind`'s existing Codable (it's used by `PenNode`'s custom Codable).

**Dependencies:** None

### Task 1: Clock primitives

**Tests first (`LamportClockTests.swift`, `TimestampTests.swift`, `VectorClockTests.swift`):**
- LamportClock: tick increments, witness updates to max(local,remote)+1, witness with lower value still increments
- Timestamp ordering: same time different peers, different times, equal timestamps
- PeerID: generate produces unique IDs, Comparable works lexicographically
- VectorClock: dominates (true, false, concurrent), merge = component-wise max, increment for peer

**Implementation:**
- `LamportClock` — `struct: Friendly, Comparable`. `var time: UInt64`. `mutating func tick() -> UInt64`, `mutating func witness(_ remote: UInt64)`
- `PeerID` — `struct: Friendly, Comparable`. `let rawValue: String`. `static func generate() -> PeerID`
- `Timestamp` — `struct: Friendly, Comparable`. `let time: UInt64`, `let peerID: PeerID`. Compare by time, then peerID.
- `VectorClock` — `struct: Friendly`. `var entries: [PeerID: UInt64]`. `dominates(_:)`, `merge(_:)`, `increment(for:)`

**Dependencies:** None. Can run in parallel with Task 0.

### Task 2: LWW Register

**Tests first (`LWWRegisterTests.swift`):**
- Higher timestamp wins
- Stale write (lower timestamp) is rejected, returns false
- Tie-breaking: same time, higher peerID wins
- Equal timestamp: no change (idempotent)
- Convergence: two registers set in opposite orders converge to same value

**Implementation (`LWWRegister.swift`):**
```
struct LWWRegister<Value: Friendly>: Friendly {
    private(set) var value: Value
    private(set) var timestamp: Timestamp
    @discardableResult mutating func set(_ newValue: Value, at newTimestamp: Timestamp) -> Bool
}
```

**Dependencies:** Task 1

### Task 3: LWW Property Map + Property Diffing

**Tests first (`LWWPropertyMapTests.swift`, `PropertyDiffTests.swift`):**
- LWWPropertyMap: accept newer timestamp for a property, reject older, independent properties don't interfere with each other
- PropertyDiff for common: change only name → `{"common.name"}`, change multiple → correct set, no changes → empty set
- PropertyDiff for kind: change width on frame → `{"kind.width"}`, different kind cases → returns all keys of both kinds

**Implementation:**
- `LWWPropertyMap` — maps property path strings (`"common.name"`, `"kind.width"`) to `Timestamp`. `shouldAccept(property:at:)`, `record(property:at:)`.
- `PropertyDiff` — `diffCommon(old:new:) -> Set<String>` compares each of PenNodeCommon's 13 fields. `diffKind(old:new:) -> Set<String>` compares kind-specific fields (switches on kind case; if different cases, returns all keys).

**Dependencies:** Tasks 1, 2

### Task 4: RGA List

**Tests first (`RGAListTests.swift`):**
- Insert at beginning, middle, end — correct ordering in `elements`
- Delete (tombstone) — element removed from `elements` but entry preserved
- Concurrent inserts at same position — deterministic interleaving (descending timestamp = newer leftmost)
- Move within list (delete + re-insert)
- Convergence: two RGA instances with same ops in different orders produce same `elements`
- Insert after tombstoned position
- Empty list operations

**Implementation (`RGAList.swift`):**
- `PositionID` — wraps `Timestamp`, `Comparable`
- `Entry` — `positionID`, `value`, `isDeleted` (tombstone), `afterID` (the position this was inserted after)
- `insert(_:after:timestamp:)`, `insert(_:atIndex:timestamp:)`, `delete(positionID:)`, `delete(atIndex:)`, `move(positionID:after:timestamp:)`, `positionID(atIndex:)`, `positionID(for:)`
- `var elements: [Element]` — non-tombstoned entries in order
- Insertion algorithm: find predecessor, scan right past entries with higher IDs, insert

**Dependencies:** Task 1. Can run in parallel with Tasks 2, 6.

### Task 5: CRDTOperation + OperationLog

**Tests first (`CRDTOperationTests.swift`, `OperationLogTests.swift`):**
- CRDTOperation: round-trip serialization of every Payload case
- OperationLog: appendLocal increments clock and returns operation with correct timestamp, appendRemote advances witness clock, `pending(since:)` returns correct subset, `truncate(acknowledgedBy:)` removes acknowledged ops

**Implementation:**
- `CRDTOperation` — `struct: Friendly`. Fields: `id: Timestamp`, `dependencies: VectorClock`, `payload: Payload`. The `Payload` enum has cases: `setProperty`, `listInsert`, `listDelete`, `listMove`, `treeMove`, `createNode`, `deleteNode`, `setVariable`, `removeVariable`, `setImport`, `removeImport`, `setThemeAxis`, `removeThemeAxis`. Each case carries a small `Friendly` struct with the operation's parameters.
- `OperationLog` — `struct: Friendly`. Append-only log with `clock: LamportClock`, `vectorClock: VectorClock`, `peerID: PeerID`. `appendLocal(_:)`, `appendRemote(_:)`, `pending(since:)`, `truncate(acknowledgedBy:)`.

**Dependencies:** Tasks 1, 2, 4 (needs `RGAList.PositionID` type in some payload structs)

### Task 6: Kleppmann Tree Move

**Tests first (`TreeMoveCRDTTests.swift`):**
- Simple move: A from root to B's children — accepted
- Cycle detection: A is parent of B, move B to be parent of A — rejected
- **Concurrent cycle-creating moves (CRITICAL):** peer1 moves A under B, peer2 moves B under A. Apply in both orders on two replicas. Assert both replicas converge. One move accepted, one rejected.
- Three-node cycle: A→B→C, concurrent move C under A — detected
- Move to root: always safe
- Late-arriving operation triggers rebuild and produces correct state

**Implementation (`TreeMoveCRDT.swift`):**
Following Kleppmann 2020. Everything is a `Move(timestamp, nodeID, newParentID)`.
- `MoveOp` — `struct: Friendly, Comparable`. `timestamp`, `nodeID`, `newParentID: String?` (nil = root).
- `LogEntry` — `MoveOp` + `oldParentID: String?` (for undo).
- State: `parentMap: [String: String?]` (nodeID → parentID), `moveLog: [LogEntry]` in timestamp order.
- `applyMove(_:) -> Bool` — insert into log at correct position. If latest, just check cycle and apply. If not latest, rebuild from scratch (undo-redo replay per Kleppmann).
- `wouldCreateCycle(nodeID:newParentID:)` — walk up parent chain from `newParentID`; if we hit `nodeID`, it's a cycle.
- `rebuild(existingNodes:)` — replay all moves from log start, skipping cycle-creating ones.

**Dependencies:** Task 1. Can run in parallel with Tasks 2, 4.

### Task 7: CRDTDocument integration layer

**Tests first (`CRDTDocumentTests.swift`):**
- processLocal for `insertNode` produces `createNode` + `listInsert` CRDTOperations
- processLocal for `deleteNode` produces `deleteNode` + `listDelete` ops, tombstones the node
- processLocal for `moveNode` produces `treeMove` + list ops
- processLocal for `updateCommon` diffs and produces per-property `setProperty` ops
- processLocal for `updateKind` diffs and produces per-property `setProperty` ops
- processRemote for a `setProperty` on a live node returns mutations
- processRemote for a `setProperty` on a tombstoned node returns nil (no-op)
- processRemote for a `treeMove` that would create a cycle returns nil

**Implementation:**
- `CRDTDocument` — `@MainActor final class`. Properties: `peerID`, `clock`, `vectorClock`, `operationLog`, `propertyMaps: [String: LWWPropertyMap]`, `childrenLists: [String: RGAList<String>]` (key is parentID or `"__root__"` for rootOrder), `treeMove: TreeMoveCRDT`, `tombstones: Set<String>`, `variableTimestamps/importTimestamps/themeTimestamps: [String: Timestamp]`.
- `processLocal(operation:document:) -> [CRDTOperation]` — translates an `EditOperation` into CRDT operations. For `updateCommon`/`updateKind`, diffs old vs new to produce per-property ops. For structural ops, produces the appropriate CRDT ops.
- `processRemote(operation:document:) -> [DocumentMutation]?` — applies a `CRDTOperation` to CRDT state, returns mutations for the flat store (or nil if no-op).
- `pendingOperations(since:) -> [CRDTOperation]`
- `DocumentMutation` enum — `setNode`, `removeNode`, `setChildren`, `setParent`, `removeParent`, `setVariable`, `removeVariable`, `setImport`, `removeImport`, `setThemeAxis`, `removeThemeAxis`

**Dependencies:** Tasks 1–6

### Task 8: Wire into EditableDocument

**Tests first (`EditableDocumentCRDTTests.swift`):**
- Create document with peerID → `crdtDocument` is non-nil
- Create document without peerID → `crdtDocument` is nil, `apply()` works as before
- `applyLocal()` produces `CRDTOperation`s and updates flat store
- `applyRemote()` with property change updates flat store
- `applyRemote()` with stale property change is a no-op
- `applyRemote()` with delete tombstones the node
- Materialize after remote ops produces correct PenDocument

**Implementation:**
- Add to `EditableDocument.swift`: `public internal(set) var crdtDocument: CRDTDocument?` and `public init(from document: PenDocument, peerID: PeerID)` (initializes CRDT state from existing flat store).
- `EditableDocument+CRDT.swift`: `applyLocal(_:) throws -> [CRDTOperation]`, `applyRemote(_:)`, `applyRemote(_: [CRDTOperation])`, `pendingOperations(since:) -> [CRDTOperation]`, internal `applyMutation(_: DocumentMutation)`.

**Dependencies:** Task 7

### Task 9: Convergence tests

**Tests (`CRDTConvergenceTests.swift`, `CRDTConcurrentMoveTests.swift`, `CRDTConcurrentDeleteTests.swift`):**

Helper: `makePair(from:)` creates two `EditableDocument`s from the same `PenDocument` with different peerIDs. `assertConverged(_:_:)` checks same node IDs, same node data, same children ordering, same rootOrder, same variables/imports/themes.

**Convergence scenarios:**
- Two peers edit different properties of same node → both edits preserved
- Two peers edit same property → LWW resolves, both converge
- Two peers insert at same position in same list → deterministic interleaving
- Property-based random: N random ops on A, M random ops on B, exchange, assert converged

**Concurrent move scenarios:**
- A moves X under Y, B moves Y under X → cycle, one rejected, both converge
- A moves X under Y, B moves X under Z → last writer wins, both converge
- Three-way cycle

**Concurrent delete scenarios:**
- A deletes X, B edits X's properties → edit dropped, both converge
- A deletes parent, B moves child into parent → child promoted to root
- A deletes parent, B inserts child into parent → child at root

**Dependencies:** Task 8

### Task 10: Fuzz tests

**Tests (`CRDTFuzzTests.swift`):**
- Create document with ~10 nodes
- 2-3 simulated peers
- Each generates 50-100 random operations (insert, delete, move, property edit)
- Operations randomly interleaved and applied to all peers
- Assert all converge
- Multiple seeds for reproducibility

**Dependencies:** Task 9

### Task 11: Documentation

- `Sources/Woodcase/Documentation.docc/CRDTArchitecture.md` — new DocC article covering the three CRDT primitives, local/remote operation flow, convergence guarantee, how to enable collaborative mode
- Update `Woodcase.md` topics — add Sync section
- Update `EditingDocuments.md` — reference CRDT/collaborative mode
- Update `README.md` — add doc link
- Update `project/2026-04-01-editing-architecture.md` — mark Phase 2 complete with implementation notes
- Ensure all new public types have complete DocC annotations

**Dependencies:** All previous tasks

## Task Dependency Graph

```
Task 0 (Fix EditOperation serialization)  ──┐
Task 1 (Clock, PeerID, Timestamp, VectorClock) ──┤
                                               ├── Task 7 (CRDTDocument) ── Task 8 (Wire into ED) ── Task 9 (Convergence) ── Task 10 (Fuzz) ── Task 11 (Docs)
Task 2 (LWW Register)      ← Task 1 ──────┤
Task 3 (Property Map+Diff) ← Tasks 1,2 ───┤
Task 4 (RGA List)           ← Task 1 ──────┤
Task 5 (CRDT Op + Log)     ← Tasks 1,2,4 ─┤
Task 6 (Kleppmann Tree Move) ← Task 1 ────┘
```

**Parallelizable batches:**
1. Tasks 0 + 1 (parallel, no dependencies)
2. Tasks 2 + 4 + 6 (parallel, all need only Task 1)
3. Tasks 3 + 5 (parallel: 3 needs 1+2, 5 needs 1+2+4)
4. Task 7 (needs all of 1-6)
5. Task 8 → 9 → 10 → 11 (sequential)

## Verification

After all tasks:
1. `swiftformat . --lint` passes
2. `swift test --quiet` passes (all existing + new tests)
3. All Phase 1 tests still pass unchanged
4. Convergence tests pass: two replicas with same ops in any order produce identical flat stores
5. Fuzz tests pass: random operation sequences across 2-3 peers converge
6. Single-user `apply()` path still works identically (no CRDT overhead when `crdtDocument` is nil)
7. DocC generates with no new warnings: `swift package generate-documentation --target Woodcase`

## Notes for Fresh Context

- **TDD is mandatory.** Write all tests for a task first, verify they fail, then implement. If an existing test must change, explain why and get user consent.
- **Do not modify existing types** (`PenDocument`, `PenNode`, pipeline types). `EditableDocument.swift` gets a small addition (optional `crdtDocument` property + new init) but existing behavior is unchanged.
- **The `Sync/` directory does not exist yet** — create it under `Sources/Woodcase/`.
- **Sandbox must be disabled** for `swift build`, `swift test`, `swiftformat`, `mkdir`, and git commands.
- **One type per file**, extensions in `BaseType+ExtensionName.swift`, folders no more than one level deep.
- **All CRDT types should conform to `Friendly`** — they need to be serializable for the operation log. `CRDTDocument` is a class and cannot conform to `Friendly`, similar to `EditableDocument`.
- **When constructing `PenNode` in tests**, use the full initializer — no `.init()` shorthand.
- **The `@Observable` macro** requires `import Observation` (Apple-only, already used).
- **`PenValue<T>` is an enum**: use `.literal("Arial")`, not `PenValue(value: "Arial")`. `PenSizing` is also an enum: `.fixed(200)`.
- **git commands need sandbox disabled** due to `~/.gitconfig` access.
- **`EditableDocument` stored properties are `public internal(set)`** — writable from within the module (including new extensions).
- **Empty children arrays are significant.** `children[id] == nil` ≠ "can't have children." Always check `nodes[id]?.kind.canHaveChildren`.

If you need specific details from the design document, the full text is at: `project/2026-04-01-editing-architecture.md`

---

## Implementation Progress

### Completed Tasks

- **Task 0: Fix EditOperation serialization** — Created `KindEnvelope` wrapper in `EditOperation+Codable.swift` with custom Codable for `UpdateKind`. All 14 `EditOperation` cases now round-trip through JSON. Tests in `EditOperationCodableTests.swift`.
- **Task 1: Clock primitives** — `LamportClock`, `PeerID`, `Timestamp`, `VectorClock` in `Sources/Woodcase/Sync/`. All conform to `Friendly`. Tests in `LamportClockTests.swift`, `TimestampTests.swift`, `VectorClockTests.swift`.
- **Task 2: LWW Register** — Generic `LWWRegister<Value: Friendly>` with timestamp-based conflict resolution and peer ID tie-breaking. Tests in `LWWRegisterTests.swift`.
- **Task 3: LWW Property Map + Property Diffing** — `LWWPropertyMap` for per-property timestamps. `PropertyDiff` with `diffCommon(old:new:)` and `diffKind(old:new:)` covering all 14 kind cases and all 13 common properties. Tests in `LWWPropertyMapTests.swift`, `PropertyDiffTests.swift`.
- **Task 4: RGA List** — `RGAList<Element: Friendly>` with tombstone deletion, concurrent insert interleaving (higher timestamp leftmost), and convergence. Tests in `RGAListTests.swift`.
- **Task 5: CRDTOperation + OperationLog** — `CRDTOperation` with 13 payload cases. `OperationLog` with clock management, `pending(since:)`, `truncate(acknowledgedBy:)`. Tests in `CRDTOperationTests.swift`, `OperationLogTests.swift`.
- **Task 6: Kleppmann Tree Move** — `TreeMoveCRDT` with cycle detection, out-of-order rebuild, and convergence guarantees. Tests in `TreeMoveCRDTTests.swift`.
- **Task 7: CRDTDocument integration layer** — `CRDTDocument` class tying all CRDT state together. `processLocal()` translates EditOperations into CRDTOperations with property diffing. `processRemote()` applies remote ops with LWW resolution. `DocumentMutation` enum for flat store updates. Tests in `CRDTDocumentTests.swift`.
- **Task 8: Wire CRDT into EditableDocument** — Added `crdtDocument: CRDTDocument?` property and `init(from:peerID:)` to `EditableDocument`. Created `EditableDocument+CRDT.swift` with `applyLocal(_:)`, `applyRemote(_:)`, `applyRemote(_:) [batch]`, `pendingOperations(since:)`, `applyMutation(_:)`, and `reconcileChildrenWithParents()`. 12 tests in `EditableDocumentCRDTTests.swift`.
- **Task 9: Convergence tests** — Three test files covering 14 scenarios: property convergence (different props, same prop LWW, random edits), concurrent inserts, variable/import/theme convergence, concurrent moves (mutual cycle, different parents, three-node cycle), and concurrent deletes (edit-vs-delete, move-into-deleted-parent, insert-into-deleted-parent, cascade). Tests in `CRDTConvergenceTests.swift`, `CRDTConcurrentMoveTests.swift`, `CRDTConcurrentDeleteTests.swift`. Discovered and fixed: genesis peer ID bug, cascading delete bug, tree move reconciliation gap, delete-wins semantic for tombstoned parents.

### Remaining Tasks

- **Task 10: Fuzz tests** — COMPLETE. All 15 fuzz seeds pass (7 original + 8 additional), including the previously failing 3-peer seed 2026. The fix: `processLocalMove` now emits a single atomic `listMove` op (instead of separate `listDelete` + `listInsert`) and uses the tree CRDT's `parentMap` as source of truth (instead of the flat store's `parents` map). `processRemoteListMove` was also completed — it looks up the actual element value via `RGAList.value(at:)` before tombstoning, then inserts into the target list.
- **Task 11: Documentation** — COMPLETE. Created `Sources/Woodcase/Documentation.docc/CRDTArchitecture.md` DocC article. Updated `Woodcase.md` (added Sync section to topics), `EditingDocuments.md` (added collaborative editing section), `README.md` (added doc link).

### Bug Fixes from Fuzz Testing (Task 10)

The fuzz tests exposed several real convergence bugs that were fixed:

1. **Missing local timestamps for variables/imports/themes** (`CRDTDocument.swift`). `processLocal` generated CRDT ops but didn't record timestamps in `variableTimestamps`/`importTimestamps`/`themeTimestamps`. Remote LWW checks had no local timestamp to compare against, so both peers accepted each other's values. Fixed by adding `processLocalSetVariable`, `processLocalRemoveVariable`, etc. helper methods that record timestamps.

2. **RGA concurrent sibling interleaving bug** (`RGAList.swift`). The RGA scan stopped at the first entry with a different `afterID`, but those entries could be descendants of a higher-priority concurrent sibling we should be skipping. Fixed by tracking `skippedPositions: Set<PositionID>` and continuing past entries whose `afterID` is in the set.

3. **Cascade tombstoning caused divergence** (`EditableDocument+CRDT.swift`). `reconcileChildrenWithParents` cascade-tombstoned children of tombstoned parents, but this could catch nodes that a concurrent peer had moved away. Different interleaving orders caused different cascade results. Fixed by removing the cascade — only explicit `deleteNode` operations tombstone nodes. Orphaned nodes (parent tombstoned) are promoted to root.

4. **`processRemoteCreateNode` cascade-tombstoned concurrent creates** (`CRDTDocument.swift`). When a node was created with a tombstoned parent, the node was immediately tombstoned. But other peers might not have tombstoned the parent yet, leading to divergence. Fixed by creating the node at root instead.

5. **Tree move parentMap sentinel confusion** (`CRDTDocument.swift`). `processRemoteTreeMove` used `oldParentMap[nodeID] ?? nil` which collapsed "not in map" with "at root (nil parent)". When a newly-created node was moved, the tree CRDT showed no change and emitted no mutation. Fixed by explicitly checking `oldParentMap.keys.contains(nodeID)`.

6. **Reconciliation used stale flat store parents** (`EditableDocument+CRDT.swift`). Reconciliation built expected parent assignments from the flat store's `parents` map, which could diverge from the tree move CRDT. Fixed by using the tree move CRDT's `parentMap` as the authoritative source for parent assignments during CRDT-mode reconciliation.

7. **Children/rootOrder deduplication** (`EditableDocument+CRDT.swift`). RGA lists could contain duplicate node IDs (from multiple move-to-root operations). Reconciliation now deduplicates using `seen.insert(nodeID).inserted`.

### Resolved Fuzz Issue (seed 2026)

The 3-peer seed 2026 was fixed by implementing atomic `listMove`. Root cause: `processLocalMove` generated separate `listDelete` + `listInsert` ops using the flat store's parent map, which could be stale when concurrent moves were in flight. Fix:
1. `processLocalMove` now reads `treeMove.parentMap` (not `document.parents`) for the source list ID
2. Emits a single `CRDTOperation.ListMove` instead of separate delete + insert ops
3. `processRemoteListMove` uses `RGAList.value(at:)` to look up the element before tombstoning, then inserts the actual node ID into the target list
4. `RGAList.move(positionID:after:timestamp:)` now accepts `PositionID?` (nil = beginning)

### Notes for Continuation

- `AnyCodable` is an **enum** (`.null`, `.bool(Bool)`, `.int(Int)`, `.double(Double)`, `.string(String)`, `.array`, `.dictionary`), NOT a struct. Use enum cases directly.
- `PenCornerRadius` is `.uniform(PenValue<Double>)` or `.perCorner(...)`.
- All existing CRDT tests (66 tests across 8 suites) pass after the fuzz test fixes. The changes are backward-compatible.
- Files created so far in `Sources/Woodcase/Sync/`: `LamportClock.swift`, `PeerID.swift`, `Timestamp.swift`, `VectorClock.swift`, `LWWRegister.swift`, `LWWPropertyMap.swift`, `PropertyDiff.swift`, `RGAList.swift`, `CRDTOperation.swift`, `OperationLog.swift`, `TreeMoveCRDT.swift`, `DocumentMutation.swift`, `CRDTDocument.swift`.
- Files created in `Sources/Woodcase/Editing/`: `EditOperation+Codable.swift`, `EditableDocument+CRDT.swift`.
- Test files created: `EditOperationCodableTests.swift`, `LamportClockTests.swift`, `TimestampTests.swift`, `VectorClockTests.swift`, `LWWRegisterTests.swift`, `LWWPropertyMapTests.swift`, `PropertyDiffTests.swift`, `RGAListTests.swift`, `CRDTOperationTests.swift`, `OperationLogTests.swift`, `TreeMoveCRDTTests.swift`, `CRDTDocumentTests.swift`, `EditableDocumentCRDTTests.swift`, `CRDTConvergenceTests.swift`, `CRDTConcurrentMoveTests.swift`, `CRDTConcurrentDeleteTests.swift`, `CRDTFuzzTests.swift`.

### Important Implementation Notes from Tasks 8–9

These discoveries were made during convergence testing and are critical for the fuzz tests and future work:

1. **Genesis peer ID for initial RGA state.** `PeerID.genesis` (`"__genesis__"`) is used when building initial RGA lists in `CRDTDocument.init`. All peers use this peer ID for initial child ordering timestamps, so cross-peer `listDelete` references work correctly. Without this, position IDs differ between peers and list deletes silently fail.

2. **Non-cascading remote deletes.** `processRemoteDeleteNode` only tombstones the single node — it does NOT cascade to descendants. The originating peer sends separate `deleteNode` ops for each descendant, so receiver-side cascading would double-delete and incorrectly capture nodes that were concurrently moved INTO the subtree.

3. **Children/parents reconciliation after every remote op.** `reconcileChildrenWithParents()` is called after processing each remote op (or batch). It:
   - Tombstones nodes whose parent is in the CRDT's tombstone set (delete-wins cascade through tombstones)
   - Clears orphaned parent pointers (parent not in `nodes` dict)
   - Rebuilds `children` from `parents` to resolve conflicts between RGA list ops and tree move CRDT
   - Ensures `rootOrder` is consistent with `parents`

4. **Tree moves always reach the TreeMoveCRDT.** Even if the target parent is tombstoned, the `TreeMoveCRDT.applyMove()` call is NOT skipped — all replicas must process the same operations for the tree CRDT to converge. Tombstone handling happens when emitting mutations: if the tree move's resulting parent is tombstoned, the moved node is also tombstoned (delete-wins).

5. **Full parent map reconciliation on tree moves.** `processRemoteTreeMove` compares `treeMove.parentMap` before and after `applyMove`, emitting `setParent`/`removeNode` mutations for ALL changed entries — not just the current op's node. This is necessary because late-arriving ops can trigger a full log replay that affects multiple parent relationships.

6. **Delete-wins semantic.** When delete and move/insert conflict (concurrent delete of parent + move/insert into parent), delete wins. The moved/inserted child is tombstoned along with the parent. This simplifies convergence at the cost of some data loss in edge cases.

### API Summary of Built Types (for fresh context)

```
// --- Clock Primitives (Sources/Woodcase/Sync/) ---

struct LamportClock: Friendly, Comparable
  var time: UInt64 { get }
  mutating func tick() -> UInt64
  mutating func witness(_ remote: UInt64)

struct PeerID: Friendly, Comparable
  let rawValue: String
  init(rawValue: String)
  static func generate() -> PeerID
  static let genesis: PeerID  // "__genesis__" — used for initial RGA state

struct Timestamp: Friendly, Comparable
  let time: UInt64
  let peerID: PeerID
  // Ordered by time, then peerID

struct VectorClock: Friendly
  var entries: [PeerID: UInt64]
  func time(for: PeerID) -> UInt64
  mutating func increment(for: PeerID)
  func dominates(_ other: VectorClock) -> Bool
  mutating func merge(_ other: VectorClock)

// --- CRDT Primitives ---

struct LWWRegister<Value: Friendly>: Friendly
  var value: Value { get }
  var timestamp: Timestamp { get }
  init(value: Value, timestamp: Timestamp)
  @discardableResult mutating func set(_ newValue: Value, at: Timestamp) -> Bool

struct LWWPropertyMap: Friendly
  func shouldAccept(property: String, at: Timestamp) -> Bool
  mutating func record(property: String, at: Timestamp)

enum PropertyDiff
  static func diffCommon(old: PenNodeCommon, new: PenNodeCommon) -> Set<String>
  static func diffKind(old: PenNode.Kind, new: PenNode.Kind) -> Set<String>

struct PositionID: Friendly, Comparable
  let timestamp: Timestamp

struct RGAList<Element: Friendly>: Friendly
  var elements: [Element] { get }
  var count: Int { get }
  private(set) var entries: [Entry]  // Entry has positionID, value, isDeleted, afterID
  @discardableResult mutating func insert(_: Element, after: PositionID?, timestamp: Timestamp) -> PositionID
  @discardableResult mutating func insertAtIndex(_: Element, index: Int, timestamp: Timestamp) -> PositionID
  mutating func delete(positionID: PositionID)
  mutating func deleteAtIndex(_ index: Int)
  @discardableResult mutating func move(positionID: PositionID, after: PositionID?, timestamp: Timestamp) -> PositionID
  func value(at: PositionID) -> Element?
  func positionID(atIndex: Int) -> PositionID?
  func visibleIndex(of: PositionID) -> Int?

struct TreeMoveCRDT: Friendly
  struct MoveOp: Friendly, Comparable { timestamp, nodeID, newParentID: String? }
  var parentMap: [String: String?]
  init(initialParentMap: [String: String?])
  @discardableResult mutating func applyMove(_ op: MoveOp) -> Bool
  func wouldCreateCycle(nodeID: String, newParentID: String?) -> Bool

// --- Operations ---

struct CRDTOperation: Friendly
  var id: Timestamp
  var dependencies: VectorClock
  var payload: Payload
  enum Payload: Friendly — 13 cases: setProperty, listInsert, listDelete, listMove,
    treeMove, createNode, deleteNode, setVariable, removeVariable,
    setImport, removeImport, setThemeAxis, removeThemeAxis
  // Each case has a small Friendly parameter struct (e.g. CRDTOperation.SetProperty)

struct OperationLog: Friendly
  let peerID: PeerID
  var clock: LamportClock
  var vectorClock: VectorClock
  var operations: [CRDTOperation] { get }
  @discardableResult mutating func appendLocal(payload: CRDTOperation.Payload) -> CRDTOperation
  mutating func appendRemote(_ op: CRDTOperation)
  func pending(since: VectorClock) -> [CRDTOperation]
  mutating func truncate(acknowledgedBy: VectorClock)

enum DocumentMutation: Friendly
  case setNode(PenNode), removeNode(nodeID:), setChildren(parentID:childIDs:),
       setParent(nodeID:parentID:), removeParent(nodeID:),
       setVariable(name:variable:), removeVariable(name:),
       setImport(alias:path:), removeImport(alias:),
       setThemeAxis(name:options:), removeThemeAxis(name:)

// --- Integration ---

@MainActor final class CRDTDocument
  let peerID: PeerID
  var tombstones: Set<String>
  var propertyMaps: [String: LWWPropertyMap]
  var childrenLists: [String: RGAList<String>]
  var treeMove: TreeMoveCRDT
  static let rootListID = "__root__"
  init(peerID: PeerID, document: EditableDocument)
  func processLocal(operation: EditOperation, document: EditableDocument) -> [CRDTOperation]
  func processRemote(operation: CRDTOperation, document: EditableDocument) -> [DocumentMutation]?
  func pendingOperations(since: VectorClock) -> [CRDTOperation]

// --- Editing layer additions ---

// EditableDocument (modified)
@MainActor @Observable final class EditableDocument
  var crdtDocument: CRDTDocument? { get }  // nil when not in collaborative mode
  init(from: PenDocument)                   // existing — no CRDT
  init(from: PenDocument, peerID: PeerID)   // new — collaborative mode

// EditableDocument+CRDT.swift (new)
extension EditableDocument
  func applyLocal(_ operation: EditOperation) throws -> [CRDTOperation]
  func applyRemote(_ operation: CRDTOperation)
  func applyRemote(_ operations: [CRDTOperation])
  func pendingOperations(since: VectorClock) -> [CRDTOperation]
  func applyMutation(_ mutation: DocumentMutation)          // internal
  func reconcileChildrenWithParents()                        // internal

struct KindEnvelope: Friendly  // in EditOperation+Codable.swift
  // Standalone encoder/decoder for PenNode.Kind (bypasses PenNode.Kind.init(from:) which throws)
  // Used by EditOperation.UpdateKind's custom Codable
```
