# 2026-10-04 — Three-way document diff: design and plan

**Task:** `WNZpLr` "Three-way document diff into edit operations" in [2026-10-04-penumbra-editor-support.md](2026-10-04-penumbra-editor-support.md).\
**Source:** read-only research at Woodcase `f9105f3` by a subagent of Penumbra's main thread; decisions by the main thread under Ben's delegation.\
**Consumer:** `DocumentSession.submit(.file(...))` — [2026-10-04-document-session-design.md](2026-10-04-document-session-design.md).

## Rulings and decisions

- **Ben (2026-10-04): local wins.** A key changed both in ours (unwritten) and in theirs keeps ours' value and is reported.
- **Main thread (2026-10-04), accepting the research's recommendations:**
  1. **Moves and deletes keep a declared `children: []`** when the last child leaves (today it collapses to absent). It is a byte change for CLI `rm` (the file keeps `"children": []`), and the only way a merge can equal theirs.
  2. **Ours deleted, theirs edited:** the node stays deleted; the conflict carries theirs' subtree so Penumbra can offer "Restore claude's edit".
  3. **Ours edited, theirs deleted:** keep the node and the ancestors theirs deleted, and report it (Git's modify/delete behavior).
  4. **Value constraints (R6) live in the public planner, not in `apply`/`validate`,** so ops derived from a file that loaded fine are never refused. Recorded on the constraints task too.
  5. **No heuristic id matching.** A writer that mints new ids wholesale turns into delete-all plus insert-all; documented.
  6. **64-bit hash collisions under revision pruning are an accepted, documented risk.**

## Findings

Under `Sources/Woodcase/`.

- **Flat store.** `EditableDocument` keeps `nodes[id]` (children stripped), `children[parent]` (present even for `[]`), `parents`, `rootOrder` (`Editing/EditableDocument.swift:54-93`). `PenDocument` is `Friendly`, so "equals theirs" is value equality after `materialize()`.
- **`revision(of:)` is a deterministic content hash** (FNV-1a over canonical JSON, then children in order, then rendered components — `+Revision.swift:53-170`), so it compares independently parsed documents. Equal revision ⇒ equal content and subtree; a node's own placement lives in its parent's list; `rootOrder` only in `documentRevision`. **Hole:** declared `children: []` and absent children hash equal (`PenNode+Editing.swift:12-23`); compare declared-ness separately.

  > **Corrected 2026-10-04 (leaf xxZI1C, Ben's ruling):** the hole is closed at the source — `revision(of:)` now hashes a declared-empty container with its `"children": []`, so the change walk is purely pruned and its side scan is gone. Document tables never had the hole: `documentRevision` encodes each table as an optional, so `{}` and absent already hashed apart (pinned by `RevisionDeclarednessTests`).
- **Vocabulary.** `NodePropertyCodec` paths `common.*`/`kind.*` (`.null` clears). `PropertyDiff` (`Sync/PropertyDiff.swift:26-108`) is a per-kind key comparison; a ref has coarse keys `kind.ref`, `kind.descendants` (whole map), `kind.rootOverrides`. **Node extras are outside the vocabulary.**
- **Gaps in `EditOperation`:** no op for node extras; none for `fonts`, `version`, `fileToken`, root extras; moves/deletes collapse a declared `children: []` (`+Apply.swift:123-125`, `+Detach.swift:49,129`, `+CRDT.swift:441,459`); moves have only an absolute index.
- **Validation** (`+Validate.swift`): inserts refuse duplicate ids, need a container parent and an in-range index; moves refuse cycles. Deleting a component refuses while an instance survives outside the deleted subtree (`+Guards.swift:56-80`). `overrideDescendant` is stricter than loading; `setProperties` on `kind.descendants` only decodes. `updateKind` to a non-container must come after its children leave (`+Properties.swift:24-35`).
- **Every switch a new op case touches:** `+Apply.swift:37`, `+Validate.swift:23`, `+Inverse.swift:21`, `+CacheInvalidation.swift:128`, `Sync/CRDTDocument.swift:150`, `Files/ActivityEvent.swift:162,254`, `EditOperation+Codable.swift`.
- **Fuzz pattern:** `Tests/WoodcaseTests/CRDTFuzzTests.swift` (seeded xoshiro, `generateRandomOp` at :165, private) — extract into a shared helper.

## Design

**API** (new `Sources/Woodcase/Merge/`, pure and synchronous):

```swift
public enum DocumentMerge {
  public static func merge(base: EditableDocument, ours: EditableDocument,
                           theirs: EditableDocument) -> MergeResult
  public static func diff(from: EditableDocument, to: EditableDocument) -> [EditOperation] // merge(a, a, b)
}
public struct MergeResult: Friendly {
  public var operations: [EditOperation]   // apply in order to ours
  public var conflicts: [MergeConflict]
  public var keepsLocalChanges: Bool       // merged != theirs → the session stays dirty
}
public struct MergeConflict: Friendly {
  public enum Subject { case property(nodeID: String, path: String), existence(nodeID: String),
    parent(nodeID: String), childOrder(parentID: String?), nodeType(nodeID: String),
    variable(String), importAlias(String), themeAxis(String), document(key: String) }
  public enum Kind { case bothChanged, editedLocallyDeletedExternally,
    deletedLocallyEditedExternally, orphanedExternalInsert, componentKeptForLocalInstance, addedTwice }
  public var subject: Subject; public var kind: Kind
  public var base, ours, theirs: AnyCodable?   // the agent feed's "ben overrode X"
}
```

`EditableDocument` inputs reuse the session's warm revision caches; only theirs pays one O(n) hash. A `PenDocument` overload may wrap it. `DocumentMerge` conforms to the session's `DocumentMerger` protocol once that lands.

**Algorithm.**
1. **Two-way change sets** base→ours and base→theirs, top-down from `rootOrder`: equal revision on both sides skips the subtree; otherwise record own content (keys + extras + type), parent, children list and declared-ness, and recurse. One-sided nodes are walked fully. Document keys: variable names, import aliases, theme axes, `fonts` (one key), `version`, `fileToken`, each root-extras key.
2. **Per-key resolution:** only theirs changed → take theirs; only ours, or both equal → nothing; both differently → keep ours, report `bothChanged`. Ref overrides resolve per `(descendant, key)` and per root-override key, then emit one merged map value via `setProperties` (avoids `overrideDescendant`'s stricter guards).
3. **Existence** (B base, O ours, T theirs): B O ¬T → delete unless ours edited it or below, then keep it and its theirs-deleted ancestors, report. B ¬O T → stays deleted; report if theirs edited (carry theirs' subtree). ¬B ¬O T → insert; if its theirs parent doesn't survive, drop and report `orphanedExternalInsert`. ¬B O T → merge per key with base absent, report `addedTwice` differences. B O T whose theirs parent doesn't survive → back to ours' parent, report. A component theirs deletes while the merge keeps an instance → keep it, report `componentKeptForLocalInstance`. Delete-and-recreate of one id reads as an edit. A type change is one key `kind.type` covering all `kind.*`; if ours touched any `kind.*`, keep ours' type and report. A detach in theirs reads as delete + insert; name it in the report.
4. **Sibling order** per final parent: relative order of members common to all three — theirs' if only theirs reordered, else ours' (report `childOrder` if both); the rest go after their nearest preceding sibling from their side.
   > **Added 2026-10-04 (leaf b8hhaf, `Merge/ThreeWayResolver*.swift`):** how the resolver reads the rules above. *Edited* means a content key, a parent change, a declared-children change, or a reorder of the children the node kept; a child joining is the child's edit and a child leaving is not the container's — so a theirs insert into a subtree ours deleted reports only `orphanedExternalInsert` (topmost insert), not also `deletedLocallyEditedExternally` on the container. `deletedLocallyEditedExternally` is reported once, on the topmost node ours deleted, carrying base's and theirs' subtrees; `editedLocallyDeletedExternally` carries no values (ours' state is what stays). A component kept for a local instance keeps its whole definition and any container theirs deleted around it. Ours retyping a node theirs edited a `kind.*` key of reports one `nodeType` conflict. A both-added node's parent difference is a `parent`/`addedTwice` conflict. The resolver's output is the internal `MergeResolution` (target states, not ops); the d-seq leaf turns it into `MergeResult`.
5. **Op order:** (1) imports, theme axes, variable adds/updates, document properties; (2) `updateKind` to containers; (3) structural pass over the final tree breadth-first, inserting new subtrees or moving existing nodes to `(parent, i)` left to right — leavers drift to the tail, and descending the final tree rules out cycles; (4) `setProperties` per node (ref retargets and override maps after their components exist); (5) deletes, topmost only, component-free subtrees first; (6) `updateKind` to non-containers; (7) variable/import/theme removals. A test-only assertion checks that codec-patching ours' node yields theirs' node, catching vocabulary drift.

> **Added 2026-10-04 (leaf yNbDiU, `Merge/OpSequencer*.swift`, `Merge/DocumentMerge.swift`):** how step 5 was built. Only the child lists the resolution changes are made, ordered by depth in the merged tree (the top level first), which keeps the no-cycle argument without walking unchanged subtrees. Two gaps in the op vocabulary were closed or routed around: (a) **declared tables** — `setDocumentProperties` gained keys `variables`, `imports`, `themes` taking `{}` (declare; entries untouched) or null (leave out; refused while the table holds entries, so the inverse is sound). Removing a table's last entry still collapses it, so the sequencer predicts that and re-declares after the removals. (b) **Declared `children` on an existing node** had no op, and `updateKind` to a leaf left a stale `children[id]` behind. `UpdateKind` now drops the child list on a retype to a leaf (refusing, with `cannotHaveChildren`, a node that still holds children) and carries an optional `emptyChildren: .declared | .absent` for a container holding none; its inverse restores both. A first cut routed both through `replaceSubtree` of the node by itself, which `requireStableType` refuses for a reusable component with instances that theirs retypes — a valid file the merge then could not apply — so the op was extended instead. The CRDT carries the kind change but not the declaration, as it never replicated declared-ness. Phase 6 therefore reads "retype to leaves, then fix declared-children", both with `updateKind`. `keepsLocalChanges` is computed from one pruned walk ours→theirs against the resolution, without applying anything.

**The op seam with the session.** New cases are defined once: (a) `extras.<key>` in the `setProperties` vocabulary (per-key inverse; the CRDT already has node extras as LWW); (b) `setDocumentProperties([key: AnyCodable])` for `fonts`, `version`, `fileToken`, `extras.<key>`, with a per-key inverse; (c) declared `children: []` preserved. The diff emits absolute indices (valid in sequence); the session anchors moves for undo itself.

## Plan

`job import project/2026-10-04-three-way-diff-design.md --parent WNZpLr`.

```yaml
tasks:
  - title: "Operations the diff needs: node extras, document properties, empty children"
    ref: d-ops
    desc: |
      Design: project/2026-10-04-three-way-diff-design.md, "The op seam". Add extras.<key> to the setProperties vocabulary (NodePropertyCodec, PropertyDiff), a setDocumentProperties case (fonts, version, fileToken, extras.<key>) with per-key inverse and Codable, and keep a declared children: [] when moves/deletes/detach remove the last child (decision 1 — CLI rm now keeps "children": []; update any tests that pinned the old bytes and say why). Touch every EditOperation switch (Apply, Validate, Inverse, CacheInvalidation, Codable, Sync/CRDTDocument, Files/ActivityEvent). The CRDT maps the new case or marks it local-only, with a test.
    criteria:
      - "extras.<key> set and clear round-trip through apply and inverse"
      - "setDocumentProperties sets fonts, version, fileToken and root extras, each with an inverse, and round-trips Codable"
      - "Removing a container's last child keeps children: [] through materialize"
      - "The CRDT maps or explicitly refuses the new case, with a test"
  - title: "Pruned two-way change walk"
    ref: d-walk
    desc: |
      Design: project/2026-10-04-three-way-diff-design.md, algorithm step 1. New Merge/DocumentChanges.swift (+ helpers), Merge/ only. Internal visit counter for tests (@testable).
    criteria:
      - "Two identical ~2,000-node documents visit only the roots"
      - "A one-leaf edit visits only its spine and the siblings along it"
      - "The walk detects add, remove, reparent, reorder, type, property, extras and declared-children changes, plus document-level keys"
  - title: "Three-way resolver and MergeConflict"
    ref: d-resolve
    blockedBy: [d-walk]
    desc: "Design: project/2026-10-04-three-way-diff-design.md, algorithm steps 2–4 and decisions 2–3. Merge/ only."
    criteria:
      - "Table tests cover every existence rule and the property rules"
      - "A same-key edit keeps ours and reports base, ours and theirs"
      - "A component is kept for an instance added locally, and a theirs insert into a subtree ours deleted is dropped and reported"
  - title: "Op sequencer and the DocumentMerge API"
    ref: d-seq
    blockedBy: [d-ops, d-resolve]
    desc: "Design: project/2026-10-04-three-way-diff-design.md, API and algorithm step 5. Merge/ only, plus fixtures merge-rewrite-base.pen / merge-rewrite-theirs.pen (wholesale rewrite: reparent, swapped nesting, type change, component delete, emptied container, variables, fonts)."
    criteria:
      - "Applying the ops for the rewrite fixture pair to base materializes equal to theirs"
      - "With a local edit in ours, the merged result keeps it and reports the same-key conflict"
      - "Re-merging theirs into the result yields no ops"
  - title: "Merge fuzzing and docs"
    ref: d-fuzz
    blockedBy: [d-seq]
    desc: "Design: project/2026-10-04-three-way-diff-design.md. Extract a shared seeded RandomEditGenerator from CRDTFuzzTests; DocC article on the merge rules table, including decisions 5 and 6."
    criteria:
      - "Seeded runs (~12 seeds × 50 ops per side) never throw on apply and satisfy the per-key oracle"
      - "When ours equals base the result equals theirs; when theirs equals base there are zero ops"
      - "Edits in disjoint subtrees merge equal to replaying theirs' ops onto ours"
      - "A DocC article documents the merge rules"
```
