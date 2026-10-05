# Merging Documents

Fold an external version of a document into the local one, key by key, as ordinary
edit operations.

## Overview

When an agent rewrites a .pen file that an editor also has open, the editor holds three
versions of one document: the **base** both sides started from (what it last read or
wrote), **ours** (the local document, possibly with unsaved edits), and **theirs** (the
file as it now stands on disk). ``DocumentMerge/merge(base:ours:theirs:)`` takes every
change theirs made and keeps every change ours made. Where both changed the same thing
differently, **the local change wins** and a ``MergeConflict`` says so.

```swift
let result = DocumentMerge.merge(base: lastWritten, ours: local, theirs: onDisk)
for conflict in result.conflicts {
    print(conflict.subject, conflict.kind, conflict.base, conflict.ours, conflict.theirs)
}
```

The ``MergeResult`` holds ``EditOperation``s to apply to ours in order, so a merge is
undoable and attributable like any other edit. An editor applies them through its
``DocumentSession``, never through ``EditableDocument/apply(_:)`` directly.
``DocumentMerge/diff(from:to:)`` is the same merge with no local changes: the operations
that turn one document into another.

A merge is pure and synchronous, and none of the three documents changes. It is built
from two change sets, base→ours and base→theirs (see ``DocumentChanges``), and is pruned
by revision tokens: a subtree whose ``EditableDocument/revision(of:)`` matches on both
sides is never walked. So merging a small edit into a large document costs little.

Every conflict is a *report*, not a question. The merge resolves each one itself, and
the conflict carries base's, ours' and theirs' values, in the file's own JSON shape, so
a consumer can say what happened ("ben overrode claude's fill") and offer to take the
other side. `nil` means a side does not hold the subject; ``AnyCodable/null`` means it
holds it unset.

## The rules

Every rule is the same rule applied to one key: **a key only theirs changed takes
theirs' value; a key only ours changed, or both changed alike, keeps ours'; a key both
changed differently keeps ours' and is reported.** Each row below is that rule applied to
one kind of key, or an exception the structure forces.

### Keys

| Subject | What counts as one key | When both changed it differently |
| --- | --- | --- |
| A node property | One ``NodePropertyCodec`` path (`common.name`, `kind.width`) | ``MergeConflict/Subject/property(nodeID:path:)``, ``MergeConflict/Kind/bothChanged`` |
| A node extra | One `extras.<key>`: a key the file wrote that the node's type does not model | ``MergeConflict/Subject/property(nodeID:path:)`` |
| A node's type | `kind.type`, standing for *every* `kind.*` key | ``MergeConflict/Subject/nodeType(nodeID:)``; see below |
| A descendant override | One key of one descendant's entry in a `ref`'s `descendants` | ``MergeConflict/Subject/descendantOverride(nodeID:descendant:key:)`` |
| A whole-node descendant replacement | The whole entry, when any side writes one | The same subject, with a `nil` key |
| A root override | One key of a `ref`'s root overrides | ``MergeConflict/Subject/rootOverride(nodeID:key:)`` |
| A node's parent | Which node it sits under | ``MergeConflict/Subject/parent(nodeID:)`` |
| A variable, import or theme axis | One name, alias or axis | ``MergeConflict/Subject/variable(_:)``, ``MergeConflict/Subject/importAlias(_:)``, ``MergeConflict/Subject/themeAxis(_:)`` |
| A root property | `fonts` (whole), `version`, `fileToken`, each root `extras.<key>` | ``MergeConflict/Subject/document(key:)`` |
| A table's declaration | Whether `variables`, `imports` or `themes` is written, even as `{}` | ``MergeConflict/Subject/document(key:)``, keyed by the table's name |
| A container's declared `"children": []` | Whether an empty container writes the key | Cannot clash: a yes-or-no both sides changed, they changed alike |

A node **both sides added with one id** merges against an absent base: a key only one
side set is taken, and a key both set differently keeps ours' and is reported as
``MergeConflict/Kind/addedTwice``.

**Type.** A retype replaces the node's whole kind payload, so the type stands for every
`kind.*` key. If only theirs retyped the node and ours touched no `kind.*` key, the node
takes theirs' type and kind. If ours touched any `kind.*` key, the node keeps ours' type
and the clash is reported once, as ``MergeConflict/Subject/nodeType(nodeID:)``. A node
extra depends on the type — `content` is an extra on a frame and a property of a text
— so an extra of theirs that the kept type models is reported rather than written.

### Existence

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| ✓ | ✓ | deleted | Deleted — unless ours edited the node or anything under it, or added something under it (reordering its children alone does not count); then the node is kept, with every ancestor theirs deleted, each reported as ``MergeConflict/Kind/editedLocallyDeletedExternally``. |
| ✓ | deleted | ✓ | Stays deleted. If theirs edited it or anything under it, the topmost node ours deleted is reported as ``MergeConflict/Kind/deletedLocallyEditedExternally``, carrying base's and theirs' subtrees so it can be restored. |
| — | — | added | Inserted — unless its parent does not survive the merge (ours deleted it) or becomes a leaf (ours retyped it); then the topmost such insert is dropped and reported as ``MergeConflict/Kind/orphanedExternalInsert``, carrying its subtree. |
| — | added | — | Kept. |
| — | added | added | Kept, merged key by key as described above. |

*Edited* means a content key, a parent change, a change to whether the node declares its
children, or a reorder of the children it kept. A child joining a container is the
child's edit, and a child leaving is not the container's. Delete-and-recreate of one id
reads as an edit.

A node kept for a local edit keeps only the ancestors it still sits under in the merged
tree: when theirs moved the edited node out of a container theirs then deleted, that
container goes.

**Components.** A component theirs deleted while the merge still has an instance of it
(ours added or kept one) is kept with its whole definition, and any container theirs
deleted around it, reported as ``MergeConflict/Kind/componentKeptForLocalInstance``.

**Detaching.** A detach replaces a `ref` with a copy whose nodes have new ids, so a detach
in theirs reads as a delete of the instance plus an insert of the copy.

### Placement and order

- **Parent.** A move only theirs made is taken, except when theirs' new parent does not
  survive the merge (reported as ``MergeConflict/Kind/deletedLocallyEditedExternally``),
  when ours retyped that parent to a leaf, or when the move would put the node under
  itself once ours' moves are in (both reported as ``MergeConflict/Kind/bothChanged``).
  In each case the node stays under ours' parent, which is kept if theirs deleted it.
- **Children of a leaf.** A container theirs retyped to a leaf, which in the merge still
  holds children that ours gave it, keeps ours' type; the clash is reported as
  ``MergeConflict/Subject/nodeType(nodeID:)``.
- **Sibling order.** In each merged child list (and the top-level order), the members
  every side holds keep one relative order: theirs' when only theirs reordered them,
  otherwise ours'. When both reordered them it is reported as
  ``MergeConflict/Subject/childOrder(parentID:)``. Every other member goes right after
  its nearest preceding sibling on its own side; when both sides insert after one
  sibling, ours' insert stays next to it and theirs' follows.

### Component loops

Neither side can make components contain each other — an edit that would is refused —
but two sides can each add half of a loop: ours puts an instance of `Badge` in `Card`
while theirs puts one of `Card` in `Badge`. The merge resolves as above, replays its
operations on a copy of ours, and looks for a loop ours did not already hold. For each,
it traces an edge ours lacks to the external change that made it and leaves that change
out — the local side is kept — reporting it as ``MergeConflict/Kind/wouldCloseComponentLoop``:

- an external **insert** is dropped (``MergeConflict/Subject/existence(nodeID:)``, the
  subtree in ``MergeConflict/theirs``);
- an external **move** is left undone (``MergeConflict/Subject/parent(nodeID:)``);
- an external **rewrite** of a `ref`, its overrides or a `reusable` flag keeps ours'
  node (``MergeConflict/Subject/property(nodeID:path:)``, path `kind.ref`,
  `kind.descendants`, `kind.rootOverrides` or `common.reusable`).

Every other change of theirs is taken, and ``MergeResult/keepsLocalChanges`` is true. A
merge's operations may still pass through a loop *between* two of them — theirs swapped
which component holds which — so a session applies them with the loop guard off; the
result, checked whole, holds none. See <doc:ComponentLoops>.

### What a merge does not do

- **No heuristic id matching.** Nodes are matched by id and nothing else. A writer that
  mints new ids for nodes it did not mean to replace — or rewrites the whole file with
  fresh ids — reads as a delete of every old node and an insert of every new one. Local
  edits to the old nodes then surface as ``MergeConflict/Kind/editedLocallyDeletedExternally``.
  Guessing which new node "is" which old one would make the merge unpredictable, so the
  merge leaves that to the writer: keep ids stable.
- **Equal revisions are trusted.** The walk prunes any subtree whose 64-bit revision
  token is equal on both sides. Two different subtrees that hash alike would read as
  unchanged and be skipped. The chance is about one in 2⁶⁴ per comparison, and the merge
  accepts that risk rather than re-comparing pruned subtrees.

## The operations

The operations are ordered so each one applies when its turn comes:

1. Imports, theme axes and variables added or changed, then the root's properties.
2. Nodes that become containers are retyped.
3. Every changed child list is built left to right, parents first: new subtrees are
   inserted whole, and existing nodes are moved to absolute indices. A node leaving a
   list drifts to its tail until it is moved or deleted. Because a container's own place
   is final before its list is built, no move puts a node under itself; a parent and
   child that swap nesting are two plain moves.
4. Each kept node's content, as one ``EditOperation/setProperties(_:)`` per node. This
   comes after the structure, so a ref retargeted to a new component finds it.
5. Nodes that become leaves and by now hold no children are retyped. This includes an
   instance that stops being one, which must let go of its component before that
   component's delete. Then come the deletes, topmost nodes only, with subtrees holding
   no component first.
6. The remaining nodes that become leaves are retyped once their children have gone. A
   container left empty then gets or loses its declared `"children": []`, through
   ``EditOperation/UpdateKind/emptyChildren``.
7. Variables, imports and theme axes removed, then each table's declaration.

``MergeResult/keepsLocalChanges`` says whether the merged document still differs from
theirs, meaning local work survived. A session that adopted the file then stays dirty.
Merging the same external version a second time yields no operations.

## How it is tested

The table tests under `Tests/WoodcaseTests/Merge/` pin each rule. `DocumentMergeFuzzTests`
has both sides draw 50 random edits each from `RandomEditGenerator`'s merge set: retypes
both ways, declared-empty child lists and tables, node and root extras, reparenting to
explicit indices, component deletes that detach their instances, overrides and detaches.
It then checks that:

- every operation applies without a refusal;
- the result satisfies a per-key oracle that restates the rules above independently of
  the resolver;
- a second merge emits nothing;
- when ours equals base, the merge reproduces theirs exactly, and when theirs equals
  base, it emits nothing;
- edits confined to disjoint subtrees merge to the same document as replaying theirs'
  operations onto ours.

Twelve seeds run in the everyday suite. For a wider sweep, set a seed count and filter
to the suite:

```sh
WOODCASE_FUZZ_SEEDS=1000 swift test --filter DocumentMergeFuzzTests
```

## Topics

### Merging

- ``DocumentMerge``
- ``MergeResult``
- ``MergeConflict``

### Comparing

- ``DocumentChanges``
- ``NodeChange``
- ``NodeChangeKey``
- ``DocumentChangeKey``
