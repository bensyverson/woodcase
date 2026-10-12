# 2026-10-04 — Layout below root granularity: design and plan

**Task:** `x1aNTf` "Layout below root granularity" in [2026-10-04-penumbra-editor-support.md](2026-10-04-penumbra-editor-support.md).\
**Source:** read-only research by a subagent of Penumbra's main thread; decisions by the main thread under Ben's delegation.\
**Consumers:** Penumbra's reorder previews and live resize (vision R13, R17), through RapidPro's live layer ([../../RapidPro/project/2026-10-04-live-layer-design.md](../../RapidPro/project/2026-10-04-live-layer-design.md)).

## Decisions (main thread, 2026-10-04)

1. **The format has no wrap stacks** (`layout` is horizontal, vertical or none). Penumbra's spec §4.3.4 and its `reorder-wrap` fixture are struck there with a dated correction.
2. **Woodcase ships both hypothetical edits:** `.remove(X)` (the gap closes; a hugging parent shrinks during the drag) and `.move(X, i)` (room opens at i; ancestors stay put). Which one Penumbra's reorder preview uses is a UX question for Ben; Penumbra's spec §4.3.1 says the gap closes.
3. **One Sendable `PenLayoutState`** is held by both `LayoutCache` and Penumbra's pipeline. Woodcase keeps no second layout cache.
4. **`TextSizeCache` becomes public,** owned by the state, an LRU capped at ~20k entries.
5. **RapidPro gets changed rects plus moved/resized flags.** A layered rect lookup can come later if the merge cost shows.

## Findings

Under `Sources/Woodcase`.

- **`layoutIncremental`** (PenLayoutEngine.swift:103, :145) walks every root's whole subtree to find dirt (`subtreeContainsDirty` :238, O(n)), re-lays a dirty root in full, and copies clean roots (`copySubtreeRects` :248, O(subtree)). `layoutSubtree` (:192/:217) does an O(n) DFS, never revisits ancestors, and has no callers.
- **The measurement cache barely works inside stacks.** `MeasurementCacheEntry` (:270) is one entry per id keyed by available size, consulted only when `usesCache` is set (Walk.swift:94), and measure/fill passes turn it off for their whole subtree (LayoutFrame.swift:31-34). A flex child is called with `(nil, cross)` then with its resolved size, so one entry per id would thrash anyway.
- **Every insert and move is a full layout:** `invalidateAll` at EditableDocument+Apply.swift:109, :141 (also variables, themes, imports, detach).
- **Each flex container makes three passes** (measure, fill, arrange) plus absolute children (FlexLayout.swift:9-28); rects are parent-local, so a reorder changes only sibling rects.
- **Sizes propagate** up through fit_content (sum on main, max on cross) and groups (union), and down through fill shares and cross sizes. An absolute frame's fit_content does not propagate up.
- **Costs** (WoodcasePerformance.md, Release, real text): layout of `woodcase-app.pen` (974 expanded nodes) 29.1–32.1 ms; synthetic 5,000 nodes 55.3 ms; ~6 µs per text typeset. A dirty board-sized root costs 10–30 ms — over a 16.7 ms frame. No layout budget exists in `PerformanceBudgets`.
- **Probable Penumbra/Woodcase bug:** dirty ids are source ids, but the expanded tree uses `<ref>/<id>` (EditableDocument+ExpandedAddress.swift:9-27), so editing a component definition doesn't dirty its instances in other roots — their layout goes stale. Leaf 2 starts with its regression test.

> **Confirmed and fixed 2026-10-12 (leaf `bDA99O`).** `ComponentDefinitionRelayoutTests` was red on `computeLayout` and `layoutIncremental(document:)`. The equivalence oracle found five more stale-layout bugs behind it: an override evicted only the source ref id, never the instance's `R/…` nodes; a `theme` change dirtied the node and its spine but not its subtree (`invalidateSubtreeLayout` was a copy of `invalidateLayout`); toggling `reusable` was render-only; disabling a flex child left its old rect in an incremental map; and `layoutIncremental(document:)` ignored a full invalidation. One more was in the engine, and in Penumbra's pipeline today: a flex container measures a cross-axis-fill child in its measuring pass, and that pass wrote the child's descendants into the scratch map that is merged into the target, so a cache hit in the arrange pass kept the *measuring* pass's rects (`MeasurementCacheFinalityTests`). Penumbra papers over the first bug in its adapter (`EditableDocument+RenderInvalidation.swift` `instanceRoots`, `DocumentPipeline.evictInstanceMeasurements`), with a hand-rolled `<ref>/<ref target>` that is wrong for ref chains; it can drop both.
- **Penumbra** expands and resolves the whole document per edit and keeps a duplicate measurement cache (Penumbra/Penumbra/Penumbra/Canvas/DocumentPipeline.swift:53, :231-248); it uses the default measurer, so no text caching.

## Design

**Node-granular incremental layout.** `PenLayoutState` (Sendable): the resolved document; an index expanded id → (parent, index, depth) built during the full pass; rects; per node the final constraints, the unturned size and a group's box origin; a per-node size cache of up to 4 entries keyed by constraints; the bounded text cache. Every engine call may use the cache and says whether it is final (a measure call is final unless the child is a container filling the cross axis; a fill call unless it also fills the cross axis; arrange always). Non-final calls write to a throwaway store. A clean node hits on size alone for a non-final call, and for a final call only when its constraints equal the recorded final ones (then its descendants are skipped). Store reads fall back to base rects, so groups and `freeRect` work on hits.

Dirty propagation, by index: seed `parent(D)` for each dirty D; process deepest containers first at their recorded final constraints, stopping when the new (turned) size equals the old, otherwise queue the parent; siblings in the stack hit the cache and only move; a changed fill share or cross size re-lays that child, and below it unchanged constraints hit.

> **As built (2026-10-12, `njlNrI`).** The memo is `PenLayoutEngine.Memo`: per node the offer and size of its last final call (`finals` — the same map as the public `MeasurementCacheEntry` cache, so the existing `layoutIncremental(…measurementCache:)` APIs keep their types and gain the fix) and up to four sizes from non-final calls. Final-ness is as designed; every non-final call writes below its node to one discard store. A group is never skipped on a non-final size, since its parent places it by its children's rects; on a final hit its children's rects are copied from the caller's map — "store reads fall back to base rects", applied at the one reader that needs it — so neither the unturned size (the rects carry it) nor a group's box origin is kept per node. **Deepest-first propagation with an early stop is not built:** a pass walks each dirty root from the top, and every clean subtree answers from memory, so the containers laid out are exactly the dirty spines plus the descendants whose offered space changed (`PenLayoutStateTests`), but a spine container walks all its children even when a deeper change left its size alone. The budgets are met without it (figures in `WoodcasePerformance.md`); it is the next step if a deeper board needs it. No bounded text cache yet (decision 4 — leaf `df281f`). The state is `PenLayoutState`; `PenLayoutChange` carries `stats` as containers laid out, leaves sized and hits (texts typeset are not counted separately).

Dirty translation: a plain node keeps its id; a ref R becomes `R/<root>`; if `expansionCanDepend`, every root whose `revision(of:)` moved is laid out whole (the `SettledTree` rule). Insert, delete and move dirty the old and new parents instead of `invalidateAll`.

> **As built (2026-10-12, `bDA99O`).** The source record is a value, `PenLayoutInvalidation` (`everything`, `nodes`, `subtrees`, `roots`), read from `EditableDocument.layoutInvalidation`; `PenLayoutIndex` holds the expanded tree and `PenLayoutIndex.expandedIDs(for:)` translates. Two departures from the paragraph above. **A ref names its instance whole, not `R/<root>` alone:** an override or a new target can change any node of the clone, and with a per-node memo a clean-looking `R/<child>` would answer from a stale entry. **The fallback is computed at edit time from the revision closure**, not by comparing `revision(of:)` before and after: an edit whose spine holds a component, or a node some ref names, records the top-level members of `revisionDependents(of:)` — by construction the roots whose revision moves, and `LayoutInvalidationTests` asserts the two sets are equal. A `reusable` toggle now counts as a layout change (`ChangeCategory`), so it reaches the same fallback. Structural edits still record their containing board in `roots` (leaf `2lTgnU`'s root-granular scope); `PenLayoutState.update(to:invalidation:)` already handles a spine-only structural invalidation — it finds departed nodes from the old children of dirty nodes — so narrowing the structural scope is leaf `df281f`'s.

`PenLayoutChange`: `rects` (changed ids only), `moved` (same size, new origin), `resized`, `removed`, `topmost` (changed ids with no changed ancestor — what RapidPro's `produceSubtree` takes), `affectedRoots`, `stats` (containers laid out, leaves sized, texts typeset).

**Hypothetical layout.**

```swift
public enum PenLayoutEdit { case remove(String); case move(String, toIndex: Int)
  case size(String, width: Double?, height: Double?); case sizing(String, PenSizing?, PenSizing?) }
public func hypothetical(_ edits: [PenLayoutEdit]) -> PenLayoutChange   // on PenLayoutState, non-mutating
```

An overlay applied where the engine reads properties (`extractLayoutProperties`, child lists), seeding the same upward walk with cache writes to a local copy, keyed by expanded ids. It never touches `EditableDocument`. On commit, incremental layout must equal the last hypothetical so the handoff doesn't flash. Penumbra computes a reorder preview once on lift and again only when the index changes, a resize every frame; merges the change over committed rects; and hands `topmost` to RapidPro.

> **As built (2026-10-12, `UjnrLt`): not an overlay at the property reads.** The edits land on a copy of the expanded document — only the path to each edited node is rebuilt, and a container's child list is taken out of its node before it is edited so the siblings are not copied — and the same pass runs on copies of the memo and the rects. Nothing in `extractLayoutProperties` changes, and the preview cannot drift from the commit path: `HypotheticalLayoutEquivalenceTests` compares a reorder, remove, resize and fill against committing each, over every fixture. `.move` reorders within the node's parent with `MoveNode`'s index semantics; a move to another parent is not supported (the reparent gesture uses a ghost). `PenLayoutChange.applied(to:)` is the merge. A `sizing` edit takes `width:`/`height:` labels.

**Cost model.** ≈0.5 µs per child of each re-laid container + the re-sized subtree + 6 µs per typeset (≈0.1 µs on a hit). Estimates: reorder in a 3-child row ~10 µs; remove a row from a 400-row list ~0.3 ms; resize a 30-node card in it ~0.5 ms. **Budgets:** hypothetical reorder ≤1 ms, resize ≤2 ms, committed single edit ≤1 ms, Release, 2,000-node board. Command: `WOODCASE_BUDGET_STRICT=1 swift test -c release --filter PerformanceBudgets.LayoutEditTests 2>&1 | grep BUDGET`.

> **Measured 2026-10-12 (`njlNrI`, `UjnrLt`):** hypothetical reorder 0.8 ms, hypothetical resize 0.9 ms, committed text edit (`PenLayoutState.update`) 0.9 ms — release, minimum of 20, load 8–15, against 70.9 / 21.1 / 21.0 ms root-granular. Command: `WOODCASE_BUDGET_STRICT=1 swift test -c release --filter PerformanceBudgets.LayoutStateTests 2>&1 | grep BUDGET`; details and caveats in `WoodcasePerformance.md`. The cost model's 0.5 µs a child is about 1 µs a row in a 400-row list whose rows fill its width (each is asked twice).

## Plan

`job import project/2026-10-04-sub-root-layout-design.md --parent x1aNTf`.

```yaml
tasks:
  - title: "Editor-board fixture and layout budgets"
    ref: y-bench
    desc: "Design: project/2026-10-04-sub-root-layout-design.md, cost model. Tests/WoodcaseTests/Performance/SyntheticPenDocument.swift gains makeEditorBoard(nodeCount:) (stacks, fill, wrapping text, instances, a 400-row list); new PerformanceLayoutEditBudgetTests.swift; WoodcasePerformance.md. Record today's root-granularity numbers as the baseline."
    criteria:
      - "The benchmark command prints BUDGET lines for reorder, resize and committed edit on a 2,000-node board with real text"
      - "Today's baseline is recorded in WoodcasePerformance.md with the commit and uptime"
      - "The board generator is deterministic and can write a .pen that Penumbra's drag-bench loads"
  - title: "Expanded-id index, dirty translation and an equivalence oracle"
    ref: y-index
    desc: "Design: project/2026-10-04-sub-root-layout-design.md, dirty translation and the probable stale-instance bug. PenLayoutEngine.swift, Editing/EditableDocument+Layout.swift, Editing/LayoutCache.swift, new PenLayoutIndex.swift."
    criteria:
      - "A regression test (red first) shows editing a component definition re-lays out its instance in another root"
      - "A source dirty set translates to expanded ids, falling back to revision-moved roots"
      - "An oracle over each fixture and a spread of writes asserts incremental equals full layout, bit for bit"
  - title: "Node-granular layout engine with PenLayoutChange"
    ref: y-engine
    blockedBy: [y-index]
    desc: "Design: project/2026-10-04-sub-root-layout-design.md, node-granular incremental layout. PenLayoutEngine+Walk.swift, +FlexLayout.swift, +FlexFill.swift, +AbsoluteLayout.swift, +LayoutFrame.swift, new PenLayoutState.swift."
    criteria:
      - "The oracle stays green with the cache active in measure and fill passes"
      - "After one node is resized, the containers laid out are its ancestors plus fill descendants whose constraints changed (Penumbra contract)"
      - "PenLayoutChange lists exactly the ids whose rect differs"
      - "A committed single edit lays out in ≤1 ms Release on the 2,000-node board"
  - title: "Hypothetical layout overlay"
    ref: y-hypo
    blockedBy: [y-engine]
    desc: "Design: project/2026-10-04-sub-root-layout-design.md, hypothetical layout and decision 2 (ship both .remove and .move)."
    criteria:
      - "A .move hypothetical leaves documentRevision unchanged (Penumbra contract)"
      - "A hypothetical .move equals the rects after committing that move"
      - "Reorder ≤1 ms and resize ≤2 ms Release on the 2,000-node board"
  - title: "LayoutCache and structural edits on the new state"
    ref: y-cache
    blockedBy: [y-engine]
    desc: "Design: project/2026-10-04-sub-root-layout-design.md, decisions 3–4. Editing/EditableDocument+Apply.swift:109,141, LayoutCache.swift, EditableDocument+Layout.swift, a public bounded TextSizeCache."
    criteria:
      - "A move or insert within one parent no longer calls invalidateAll"
      - "computeLayout returns a PenLayoutChange"
      - "Penumbra can drop its duplicate measurement cache (DocumentPipeline.swift:53), shown by a note on the Penumbra contract leaf"
```
