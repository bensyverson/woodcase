# 2026-10-04 — DocumentSession: design and plan

**Task:** `rqBCLK` "DocumentSession: one edit funnel with per-author undo" in [2026-10-04-penumbra-editor-support.md](2026-10-04-penumbra-editor-support.md).\
**Source:** read-only research at Woodcase `f9105f3`, by a subagent of Penumbra's main thread. Design decisions were made by the main thread under Ben's delegation, after Ben's rulings below.

## Ben's rulings (2026-10-04)

1. **Shape.** `DocumentSession` is a non-Sendable `final class`, confined by its owner (Penumbra: the main actor; the CLI: its one thread). `submit` is synchronous. It hands out Sendable value snapshots for background work.
2. **Structural undo keeps theirs.** Apply what can be undone safely. When undoing would destroy another author's later work (undo an insert after `claude` edited inside the node), keep that work and report it ("Kept 1 change by claude").
3. **Merge conflicts: local wins.** When an unwritten local change and an external write touch the same key, the local value wins and the conflict is reported.
4. **Undo rules (session 3, built in `fee263a` and `9d353f6`).** Undo titles derive from the edit's activity kind, localized by the editor; `LocalEdit` has no title. An undo-excluded (`.none`) edit still clears redo. A detaching delete whose undo meets another author's edit inside one detached expansion is skipped whole: the component stays deleted and every instance stays detached. An undo or redo closes the open coalescing group. Redo rows get their own `ActivityEvent.Kind.redo`.
5. **Remote changes and local state (session 4).** `rollback(to:)` refuses, with a typed `SessionError`, when a remote change was journaled after the checkpoint: restoring the ledger would drop that change's stamps while its effects stay, so a later undo could overwrite it. Checkpoints are CLI-only and non-collaborative today, so refusing costs nothing. A remote change does **not** close the open coalescing group; the local gesture stays one undo step, and keep-theirs protects the remote values on undo.

## Main-thread decisions (2026-10-04)

- **An author is a name plus a per-replica `PeerID`.** Ben in two windows is two authors for undo; reports show the name only.
- **`woodcase undo` (log-driven) is unchanged** and still stops at `blockedByOther`. Revisit once the log carries forward ops (`NtYiGz`).
- **Logged inverses change shape** (granular `setProperties` instead of whole `updateCommon`; complete detach inverses). Old rows still decode and replay. Document it in WoodcaseActivityLog.md.
- **CRDT override granularity stays the whole map** here; splitting it is `hXjCIZ`'s job (flag it there).
- **Undo coalescing lives in the session** (`UndoGroup`). Penumbra's `UndoManager` only mirrors titles and the dirty state.
- **The intent type is `[EditOperation]` for now.** The public planner (`2gTcuM`) later adds `LocalEdit.init(planning:in:)`; `SessionOrigin` does not change.

## Findings that shape the design

File references are under `Sources/Woodcase/`.

- **`revision(of:)` is a content hash** (FNV-1a of the subtree plus the components it renders, `Editing/EditableDocument+Revision.swift:53`). It has no order and suffers ABA, so it cannot answer "changed since". **The rulings' "checked by revision" is implemented with a session-owned sequence ledger**; `documentRevision` stays the hash for the log and the merge base.
- **`EditOperation`** (`Editing/EditOperation.swift:13–68`) has 19 cases and is already the log's wire format. `setProperties` is per key; `updateCommon`/`updateKind` are whole structs.
- **Inverses are snapshots** (`Editing/EditableDocument+Inverse.swift`): whole structs (:138–157), absolute indices for move/delete (:68–122), whole override entries (:187–219).
- **The detach bug is wider than the plan said.** `completeDetachInverse` (:272) and `completeDetachingDeleteInverse` (:290) have no callers. `rm --detach` plans N `.detachRef` ops plus a delete (`Batch/BatchApplier+Plan.swift:85–103`); each logs a partial inverse, and `BatchApplier.unwind` (`BatchApplier.swift:290`) and `replay` (:249) replay the same partial inverses, so a failed batch line holding a detach does not roll back cleanly.
- **Detach ids are random and unchecked.** Two independent draws (`+Detach.swift:108`, `+CRDT.swift:101`) through `PenID.remapIDs` with `avoiding: []`, so a detach can collide with an existing id.
- **`applyRemote` returns nothing** (`+CRDT.swift:199,216`), so the session can't see remote mutations' subjects.
- **A move's subjects list only the new parent** (`+CacheInvalidation.swift:138`); the change value must capture the old parent itself.
- **CRDT overrides replicate as the whole map** (`Sync/CRDTDocument+LocalProcessing.swift:264–318`).
- **No identity ↔ `PeerID` mapping exists.** `UndoStep` is already a type name (`Files/ActivityUndo.swift`).

## Design

New directory `Sources/Woodcase/Session/`, one type per file, each under ~300 lines.

**Identity.** `Author: Friendly { name: String; peerID: PeerID }`, `static func unattributed(peer:)`. `name` is the log identity (`""` unattributed).

**Origins.** `enum SessionOrigin: Sendable`:
- `.local(LocalEdit)`
- `.file(PenDocument, author: Author?)` — author from the log when the follow API matched the write; nil means external
- `.remote([CRDTOperation], from: Author)`
- `.undo`, `.redo`

`LocalEdit: Sendable { operations: [EditOperation]; expecting: [String: String]; activityKind: ActivityEvent.Kind?; undoGroup: UndoGroup }`, `UndoGroup = .new | .coalesce(String) | .none`.

**`DocumentSession`** (non-Sendable `final class`):
- `init(document: PenDocument, author: Author, file: URL?, collaborative: Bool, merger: (any DocumentMerger)?)`
- `@discardableResult func submit(_ origin: SessionOrigin) throws -> CommittedChange`
- `var document: EditableDocument { get }` (read-only use by the owner)
- `func snapshot() -> DocumentSnapshot` — Sendable: `PenDocument`, `sequence`, `documentRevision`
- `func noteSynced(_ written: PenDocument, through sequence: UInt64)` — advances the merge base after a save or a merge
- internal `checkpoint() -> SessionCheckpoint` / `rollback(to:)` — reverts document, ledger, events and undo stacks together (BatchApplier's line rollback)

**`CommittedChange`** (Friendly): `origin: OriginKind`, `author`, `applied: [AppliedOperation { forward; inverse: [EditOperation] }]` (forward normalized, inverses complete), `invalidation: ChangeInvalidation { nodes; category: ChangeCategory?; documentLevel: Set<DocumentField>; structural; full }`, `sequence: UInt64`, `documentRevision: String`, `activity: [ActivityEvent]` (local, undo, redo only — and they carry the forward ops once `NtYiGz` adds `forward`), `broadcast: [CRDTOperation]`, `isUndoable`, `isDirtying`, `kept: [KeptChange { key: ChangeKey; author: Author }]`, `conflicts: [MergeConflict]`.

**The ledger.** `ChangeKey: Hashable, Sendable` = `.property(node, path)`, `.override(ref, descendant, key)`, `.rootOverride(ref, key)`, `.placement(node)`, `.existence(node)`, `.variable(name)`, `.importAlias(a)`, `.themeAxis(n)`, `.document(key)` (fonts, version, fileToken, root `extras.<key>`, from the diff's new `setDocumentProperties`; node extras are `.property(node, "extras.<key>")`). `ChangeLedger` (internal) maps `ChangeKey → Stamp { author; sequence }`. Every applied op stamps its keys via `ChangeKey.keys(of:in:)`; remote ops stamp from CRDT payloads (SetProperty → property, treeMove → placement, create/delete → existence).

**Granular inverses.** `EditOperation.normalized(in:)` rewrites `updateCommon` and same-case `updateKind` as `setProperties` of only the changed paths (via `PropertyDiff`), so forward ops, inverses and CRDT ops share one vocabulary. A kind-case change stays a whole `updateKind` keyed `.property(node, "kind")`. `GuardedInverse { operation; keys: [ChangeKey]; placement: Placement? }`, `Placement { parentID; after: String? (sibling anchor); fallbackIndex: Int? }` — the anchor is resolved to an index at undo time, so no new `EditOperation` case and no wire change. Override inverses split per key (restore old value, or unset an added key). `prepareInverse` stays for API compatibility.

**Undo: keep theirs.** `UndoEntry { sequence; label; steps: [GuardedInverse] }`; the session holds the local author's undo and redo stacks.
- A property or override key whose stamp is newer than the entry and by another author is dropped from the step and reported in `kept`.
- A structural step is skipped (kept, reported) when any foreign newer stamp falls in its scope: undo-insert → subtree(X) ∪ placement(X); undo-detach → the expanded subtree; undo-replace → the subtree; undo-move → placement(X) foreign-newer or old parent gone; undo-delete (re-insert) → parent gone or an id taken again.
- Applied steps go through the same apply/CRDT path; their inverses build the redo entry. A new local edit clears redo.

**`.file`.** The session calls the three-way diff ([2026-10-04-three-way-diff-design.md](2026-10-04-three-way-diff-design.md)) with base = the last synced document (kept as an `EditableDocument` so its revision cache stays warm), ours = the live document, theirs = the parsed file. The diff derives "our unwritten changes" itself from base→ours, so no `protecting` set is passed; local wins per key. The diff owns `MergeResult` and `MergeConflict` (in `Merge/`). The session applies the ops under the file author, stamps the ledger, pushes no undo, sets base = theirs, and copies the conflicts into the change. A `DocumentMerger` protocol in `Session/` (`merge(base:ours:theirs:) -> MergeResult`) keeps the session testable with a stub; the diff's `DocumentMerge` conforms.

> **Correction, 2026-10-04 (main thread, same day):** the first draft passed `protecting: Set<ChangeKey>` and defined its own `DocumentMerge`/`MergeConflict`. The diff's research showed it computes local changes from base→ours, so the set is redundant, and one type per concept lives with the diff.

> **Added 2026-10-04 (leaf 2oUqxH, `Session/DocumentSession+File.swift`):** how `.file` was built. `DocumentMerge` is a caseless enum of static functions, so it cannot conform to an instance-method protocol from outside `Merge/`; `ThreeWayMerger` in `Session/` is the value that stands for it, spelled `merger: .threeWay`. The merger is an `init` parameter, `nil` by default (CLI sessions never merge). A `nil` file author is credited to `Author.external` (unattributed, peer `__external__`) so keep-theirs treats outside writes as foreign. Errors: `SessionError.mergeUnavailable` (no merger) and `fileStateUnknown` (merge base `.unknown`; also thrown by the app save, ZEAWVY); `unsupportedOrigin` is gone, as every origin is now supported. A merge writes no activity, pushes no undo and leaves redo and the open group alone, like a remote change; in collaborative mode its ops broadcast. Dirty state follows `MergeResult.keepsLocalChanges`: false syncs the session to the file, true makes the change dirtying. A failed op unwinds the merge and leaves the base where it was; an empty merge keeps the sequence but still advances the base.

**`.remote`.** An internal `applyRemoteMutations(_:) -> [DocumentMutation]` in `+CRDT.swift`; a `[PeerID: Author]` registry filled on join. Causal buffering is `hXjCIZ`'s.

> **Added 2026-10-25 (leaf hXjCIZ):** causal buffering landed in the replica, not the session, so a bare `EditableDocument.applyRemote` gets it too: `CRDTDocument` holds an operation whose `dependencies` its vector clock does not dominate and ignores one it already covers, and `commitRemote` validates every operation, then applies whatever `nextDeliverable()` releases — keying and crediting each to its own author as it lands. Vector clock entries are now Lamport times (the latest applied operation's time per peer) and `dependencies` exclude the operation itself, which is what the relay plan's `covers(op id)` assumed. The `[PeerID: Author]` registry is `noteJoined(_:)`, built with `.remote` (session 4). See DocC `CRDTArchitecture.md`, "Causal Delivery".

> **Ben ruled 2026-10-25 (session 52):** (1) the vector clock meaning above stands — Ben deferred to the integrator, who kept it because it is what the relay plan (§5) assumes and what `VectorClock`'s doc comment already said; (2) a deleted node comes back under the CRDT through **existence as a last-writer-wins register per id** (leaf Re3ipI, option A): a newer create revives the node, and property writes that arrive while it is tombstoned are kept and apply when it returns, so collaborative undo of a delete converges. Not a remote-only tombstone check, which would make the divergence worse.

**Detach.** `SubtreeIDPlan.detaching(expanded, refID:, avoiding: document ids)` derives each id as base62(FNV1a(refID + "/" + expanded id)) to 5 characters, re-salting deterministically on collision. Both detach call sites use it. Then `prepareInverse` returns complete inverses before apply for detach and detaching delete, which fixes ActivityRecorder, `unwind` and `replay` with no caller changes; the two `complete*` helpers become deprecated pass-throughs.

**The CLI on the funnel.** `PenFileTransaction.run` builds a transient session (author = `--as`, file = url). `ActivityRecorder.apply` becomes `session.submit(.local(...))` and collects `change.activity`. `discardEvents`/`unwind` become `rollback(to:)`. `ActivityUndo` stays log-driven but applies through `.local(activityKind: .undo)`. Verb signatures don't change. `ZEAWVY` then adds a commit path for long-lived apps.

> **Added 2026-10-04 (leaf ZEAWVY, `Files/PenFileTransaction+Save.swift`):** the app path is `PenFileTransaction.save(_ snapshot: DocumentSnapshot, changes: [CommittedChange], to:log:timeout:) -> SaveOutcome` (`.wrote`, `.unchanged`, `.fileChanged(found:lineage:)`), `@concurrent`, taking only values so it runs off the main actor. Under the lock it compares the file's revision with `DocumentSnapshot.syncedRevision` (new; from `DocumentSession.syncedRevision`) and refuses rather than overwrite a write it has not merged; otherwise it writes `encodeForFile` bytes and appends the rows of the changes the snapshot includes, after an `external` row when the log does not explain the file. `noteSynced(_ snapshot:)` records the save and keeps the revision so the next check is free. Rows carry in-session revisions, so a file merge that kept local work, or a remote change, after the last logged change leaves no row explaining the saved file. *(Corrected same day: a first cut left this as a known gap; the coordinator ruled it in scope.)* The save then appends an `ActivityEvent.Kind.merge` row under the saving identity, with the saved revision, the folded-in nodes, their forward ops and — for file merges only — their inverses. `LogLineage` accepts it unchanged; `UndoStep.decide` steps over it for every identity (`.stepOverMerge`); `ActivityUndo` replays its inverse on a scratch copy to judge the session's rows below it exactly, so `undo --as ben` reverses ben's rows and keeps the merged-in values. `LogLineage.writer` gives the `Author` for `.file` (peer `log:<identity>`), so the app never builds one. The app's contract is in DocC `Session.md`, "Saving from an app".

## Plan

`job import project/2026-10-04-document-session-design.md --parent rqBCLK`.

```yaml
tasks:
  - title: "Deterministic detach ids and complete detach inverses"
    ref: s-detach
    desc: |
      Design: project/2026-10-04-document-session-design.md, "Detach" and the detach findings. Add SubtreeIDPlan.detaching(expanded, refID:, avoiding:) (new Editing/SubtreeIDPlan+Detach.swift): ids = base62(FNV1a(refID + "/" + expandedID)) to 5 chars, deterministic re-salt on collision with existing document ids. Use it from Editing/EditableDocument+Detach.swift:108 and +CRDT.swift:101. Make prepareInverse return complete inverses for detachRef and detaching delete before apply; the complete* helpers become deprecated pass-throughs. Files: Editing/ (Detach, +CRDT, +Inverse, PenID, new SubtreeIDPlan+Detach). Regression tests first for the CLI symptoms.
    criteria:
      - "The same document and ref yield identical detach ids in two documents and in the CRDT and non-CRDT paths, and never reuse an existing id"
      - "prepareInverse of detachRef and of a detaching delete is complete before apply, and applying it restores materialize() exactly"
      - "woodcase rm --detach then woodcase undo restores the file bytes, and a batch line failing after a detach rolls back cleanly"
  - title: "Change keys, normalization and granular inverses"
    ref: s-keys
    desc: |
      Design: project/2026-10-04-document-session-design.md, "The ledger" and "Granular inverses". New files only: Session/ChangeKey.swift, Session/ChangeKey+Operation.swift, Editing/EditOperation+Normalized.swift, Editing/EditableDocument+GranularInverse.swift, Session/GuardedInverse.swift, Session/Placement.swift. Do not change prepareInverse. The diff's leaf "Operations the diff needs" adds `extras.<key>` property paths and a `setDocumentProperties` case; cover them in ChangeKey (`.document(key)`), adding the case when whichever lands second is integrated.
    criteria:
      - "updateCommon and same-case updateKind normalize to setProperties of the changed paths and apply equal to the original"
      - "Every EditOperation case maps to its ChangeKeys (exhaustive-switch test)"
      - "A move inverse anchored on a sibling lands correctly after a foreign sibling is inserted before it"
      - "Override inverses are per key, including unsetting added keys"
  - title: "Session core: local origin and snapshots"
    ref: s-core
    blockedBy: [s-keys]
    desc: |
      Design: project/2026-10-04-document-session-design.md, "Design" through "CommittedChange". Session/ core types (DocumentSession, SessionOrigin, LocalEdit, UndoGroup, CommittedChange, AppliedOperation, ChangeInvalidation, KeptChange, Author, ChangeLedger, DocumentSnapshot, SessionCheckpoint, SessionError), DocumentSession+Local, +Snapshot, checkpoint/rollback. Expose what subjects(of:) computes through ChangeInvalidation, capturing a move's old parent. The CRDT path only when collaborative. .undo/.redo/.file/.remote may throw "not yet supported" until their leaves land. DocC article Session.md (the funnel, the ledger, keep-theirs).
    criteria:
      - "submit(.local) returns one CommittedChange with ops, inverses, invalidation (old parent included), sequence, revision, activity events and broadcast ops"
      - "A multi-op LocalEdit failing part-way leaves document, ledger and events untouched"
      - "snapshot() is Sendable and usable from a detached task"
  - title: "Per-author undo and redo that keeps theirs"
    ref: s-undo
    blockedBy: [s-detach, s-core]
    desc: |
      Design: project/2026-10-04-document-session-design.md, "Undo: keep theirs" and Ben's ruling 2. DocumentSession+Undo.swift, UndoEntry.swift. Coalescing via UndoGroup.
    criteria:
      - "Undo after another author's later write to the same key keeps their value and reports the key and author"
      - "Undoing an insert or a detach after a foreign edit inside it keeps the node and reports it"
      - "Detach and detaching delete round-trip through undo and redo in the session"
      - "A new local edit clears redo, and a coalesced group undoes as one"
  - title: "Remote origin"
    ref: s-remote
    blockedBy: [s-core]
    desc: |
      Design: project/2026-10-04-document-session-design.md, ".remote". DocumentSession+Remote.swift, plus an internal applyRemoteMutations(_:) -> [DocumentMutation] in Editing/EditableDocument+CRDT.swift. PeerID → Author registry. No causal buffering (hXjCIZ).
    criteria:
      - ".remote returns invalidation subjects and stamps the ledger under the mapped Author"
      - "A remote write then a local undo keeps the remote value and reports it"
      - "Remote changes are neither undoable nor dirtying"
  - title: "File origin seam for merges"
    ref: s-file
    blockedBy: [s-core]
    desc: |
      Design: project/2026-10-04-document-session-design.md, ".file", and project/2026-10-04-three-way-diff-design.md. DocumentSession+File.swift and the DocumentMerger protocol; MergeResult and MergeConflict come from the diff (Merge/). After this lands, Penumbra's contract leaf "three-way document diff" can run against the session.
    criteria:
      - "With a stub merger, .file applies its ops under the file author, pushes no undo, and advances the base"
      - "With the real diff, an unwritten local change survives a .file merge and the same-key conflict appears in the change"
      - "With no merger, .file throws mergeUnavailable"
  - title: "CLI write path through the session"
    ref: s-cli
    blockedBy: [s-detach, s-core]
    desc: |
      Design: project/2026-10-04-document-session-design.md, "The CLI on the funnel". ActivityRecorder, PenFileTransaction, BatchApplier unwind/replay, ActivityUndo. Document the new inverse shapes in WoodcaseActivityLog.md. Coordinate with NtYiGz's "forward on ActivityEvent" leaf, which also edits ActivityRecorder.swift — land after it if it is in flight.
    criteria:
      - "All existing CLI and log tests pass; file bytes and log rows are identical except for granular, complete inverses, and WoodcaseActivityLog.md says so"
      - "No write path in Files/ or Batch/ calls document.apply outside the session"
      - "--dry-run and external rows are unchanged"
```
