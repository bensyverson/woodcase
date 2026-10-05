# Edit cost proportional to the change — 2026-10-05

Leaves `tHIrpG` (remote apply) and `OWicrc` (edit inside a component), against Penumbra's
ruling R20: at most 1 ms of main-thread time per edit, local or remote.

## What cost the time

Both had one cause. Every `DocumentSession` commit reads `EditableDocument.documentRevision`,
a Merkle hash over the root nodes' revisions. A cold revision re-encodes every node as
canonical JSON: 21–31 ms on the 2,464-node perf board. Two paths dropped the whole
revision cache:

- **Edits inside a component.** `invalidatingCaches(touching:_:)` emptied both the
  expansion and the revision cache whenever an edit touched a `ref`, a component or a
  node inside one, because the instances it moves are a closure over the ref graph that
  nothing indexed.
- **Every remote batch.** `reconcileChildrenWithParents()` re-derived every parent link
  and children list from the CRDT and dropped the revision cache, and
  `ChangeInvalidation.RemoteProbe` copied and compared the document's whole tables.

The cost did not grow with history in Woodcase: 500 remote changes on the perf board
cost the same first and last (below). Whatever grows in Penumbra's burst is not the
session's remote apply.

## What changed

- **A revision closure.** `ComponentReferrers` indexes the reverse of
  `PenNode.renderedComponentIDs`, kept exact by `invalidatingCaches(touching:_:)` from each
  subject's content. `revisionDependents(of:)` walks up from the subjects through
  parents and referrers; an edit forgets exactly that closure's revisions and its
  instances' expansions. The component loops memoized with the expansions drop only when
  the component graph can change (`invalidatesComponentLoops(_:before:after:)`). The
  structural layout scope finds the boards drawing a component through the same closure,
  instead of a pass over every node.
- **Encodings outlive revisions.** `RevisionCache.encodings` keeps each node's hashed
  canonical encoding and the ids it renders, forgotten only when the node is written, so
  refolding a forgotten instance or ancestor costs string combines, not JSON.
- **A scoped reconciliation.** Every remote write is noted in a `FlatStoreJournal` before
  it lands; `reconcileChildrenWithParents(after:)` settles only the nodes and lists the
  journal names, by the whole pass's rules; `RemoteProbe` compares only the journal's
  entries. A batch that moves nothing reconciles nothing.

Scoping the reconciliation is exact only while the flat store agrees with the CRDT before
the batch, and **local edits can break that**: `processLocalInsert` and `processLocalMove`
map a flat index to an RGA position counting live entries the flat store does not hold,
and a redo that re-creates a tombstoned id (a collaborative detach) is placed by the CRDT
at the root. The whole-document pass used to hide both at the next remote batch. Now
`applyLocal` checks its own footprint against the CRDT and marks the store unsettled when
they disagree; the next batch reconciles whole, once, as before. The two divergences are
pre-existing; they are filed as `doNRb5`.

## Figures

Release builds, `swift test -c release -Xswiftc -enable-testing`, provisional: other agents
were building throughout. Medians of 40 edits (component probe) or of the stated window
of 500 (remote probe).

| Edit | Before (`85daec4`) | After | Load |
|---|---|---|---|
| Collaborator recolor, window applies (first 50 / 225–275 / last 50) | 23.7 / 24.2 / 24.2 ms | 0.140 / 0.136 / 0.135 ms | 9–37 → 8–11 |
| Window nudge, collaborator applies (same windows) | 23.7 / 24.0 / 24.2 ms | 0.082 / 0.080 / 0.079 ms | 9–37 → 8–11 |
| Set x inside a component | 12.9 ms | 0.77 ms | 7–86 → 8–11 |
| Insert a rectangle inside a component | 13.4 ms | 0.84 ms | 7–86 → 8–11 |
| Insert inside a component, layout cache primed (as Penumbra does) | — | 1.17 ms | 8–11 |
| Set x / insert on the page | 0.08 / 0.05 ms | 0.06 / 0.04 ms | 7–86 → 8–11 |

```sh
WOODCASE_REMOTE_COST_BOARD=<dir>/perf-large.pen swift test -c release -Xswiftc -enable-testing --filter RemoteApplyCostProbe   # board: Penumbra's scripts/perf-board <dir>
WOODCASE_LOOP_COST_PROBE=1 swift test -c release -Xswiftc -enable-testing --filter ComponentLoopEditCostProbe
```

## Where the remaining time goes

An edit inside `C5` of the component probe's document genuinely moves 512 revisions: 25
components nest it, 400 instances on the page draw one of them, and their 60 boards and
the page hold those. Split (release, load about 10, a temporary probe timing each step):
the closure walk 0.11 ms, forgetting it 0.18 ms, the apply around it 0.22 ms, and the
commit's `documentRevision` refolding the 512 nodes 0.56 ms — 0.80 ms in all. The refold
is now string combines and dictionary lookups per node; the next step down would store
revisions as `UInt64` and render hex only at the API. With the layout cache primed, the
structural layout scope reads the closure once before and once after the insert, which is
the extra 0.33 ms.

## Not done

- **(a) A subset-of-roots expand/resolve usable off the main actor.** Not built: Penumbra
  already expands per top-level board on its pipeline actor from a `PenDocument` value, and
  the shape of a Woodcase API for it wants its caller's design.
- **(b) `layoutIncremental` copies every rect when nothing is dirty.** Penumbra's pipeline
  already returns the previous rects when nothing is dirty for layout
  (`DocumentPipeline.incrementalLayout`). With one root dirty, the other roots' rects are
  still copied; starting from the previous rects instead needs to know which rects belong
  to roots that are gone, which the engine's signature does not carry.
- The tree CRDT's `processRemoteTreeMove` diffs the whole parent map on every remote
  move, and a batch that creates or removes a node scans that map once for the nodes it
  places. Both are O(document) for structural remote edits only.
