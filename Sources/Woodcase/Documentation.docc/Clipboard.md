# Copy and Paste

A copy takes the selected nodes out of a document as a clip: a .pen that draws on its
own, carrying every component, variable and theme axis those nodes need. A paste plans
taking a clip into a document, reusing what the document already has.

## Overview

An editor's Copy hands ``PenClip/extract(nodeIDs:from:documentID:)`` the ids it has selected and
puts the whole clip on the pasteboard as JSON — not only its ``PenClip/document`` — so a
paste can tell the copied roots (``PenClip/contentIDs``) from the definitions carried for
them, and keep each root's ``PenClip/origins``; `woodcase clip` prints the clip's document. Paste is the other half: ``PenClip/plan(into:at:)`` takes a clip and a target
document and returns the operations that bring it in (<doc:Clipboard#Pasting>); `woodcase paste`
applies them to a file. The rules below are Penumbra's interaction spec §16 and its
session 18 ruling.

```swift
let clip = try PenClip.extract(nodeIDs: selection, from: document, documentID: windowDocumentID)
pasteboard.setData(try JSONEncoder().encode(clip), forType: clipType)
```

### What a clip holds

The clip's roots are the copied subtrees first, named by ``PenClip/contentIDs`` in
document order, then the component definitions carried along for them. Its `variables`
and `themes` hold exactly what those roots need, and it has no `imports`.

| Copied | Comes out as |
|---|---|
| A stored node | Its subtree as stored, ids unchanged — unless it was copied out of a component the clip also carries, which would hold it twice; then it takes derived ids of its own |
| A node under another copied node | Nothing more: it travels inside the outer one |
| A node that was not a root | A root at the canvas position it was drawn at; a `fill_container` width or height becomes the size it was drawn, its original kept in the root's ``PenClip/Origin`` for a paste into a stack; `layoutPosition` is dropped. Its offset in its parent — the point its `x` and `y` named there, as drawn, so a stack child records where the stack put it — goes in its ``PenClip/Origin`` |
| An instance (a `ref`, or its expanded root id) | The `ref`, still linked, with its component carried |
| A node inside an instance | Its drawing — overrides applied, nested instances expanded — detached, under ids derived as a detach derives them (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``) |
| A component from an imported library | A local definition under its prefixed id (`K:Chip1`), with the library variables it uses (`$K:accent`) |

The ids ``PenClip/extract(nodeIDs:from:documentID:)`` takes are the expanded document's — the ones
a canvas selects and hit-tests (``EditableDocument/expandedID(of:)``) — and a stored
node's own id is accepted as well. A position is the canvas point a root's `x` and `y`
name, its own origin: a node keeps its own turn, but a turn it inherited from an
ancestor is not carried.

### Where each copy came from

Each copied root has a ``PenClip/Origin`` in ``PenClip/origins``, which a Paste in Place
reads:

| Field | A node copied out of a parent | A root copied from the top level |
|---|---|---|
| ``PenClip/Origin/parentID`` | The parent's stored id; for a node drawn inside an instance, the expanded id of the node it was drawn under, which no paste can write into | `nil` |
| ``PenClip/Origin/offset`` | Its offset in that parent | `nil` |
| ``PenClip/Origin/boardID`` | Its board: the stored root above it | `nil` |
| ``PenClip/Origin/boardOffset`` | Its offset from the board's top-left corner, in the board's coordinates | Its canvas position: the offset from the canvas origin |
| ``PenClip/Origin/nodeID`` | The id it had in the source | The same |
| ``PenClip/Origin/index`` | Its place among the parent's children (`nil` when drawn inside an instance) | Its place among the roots |
| ``PenClip/Origin/width``, ``PenClip/Origin/height`` | The `fill_container` sizing it had, which the clip writes at its drawn size; `nil` otherwise | `nil`: a root keeps its own sizing in the clip |

Every offset is the point the root's `x` and `y` named, as drawn — its own origin, so a
node a stack placed records where the stack put it.

**The document is named by the editor.** A .pen file stores no identity of its own: its
`fileToken` is a per-save token another editor writes and rewrites, not a name, and
Woodcase never generates one. So ``PenClip/extract(nodeIDs:from:documentID:)`` takes
whatever id the copying editor gives its document — any string that stays the same
while it is open, such as one made when the window opens — and records it as
``PenClip/sourceDocumentID``. The editor names its document again when it pastes
(``PasteTarget/whereCopied(documentID:)``); equal ids mean the copy is home, where its
parent ids still mean what they meant. A clip given no id is never taken to be home.

### Components

Every component the copy renders comes along — an instance's component, one an
override repoints to, an instance written as slot content — and then every component
*those* render, so nested instances and ref chains are followed to their ends
(``EditableDocument/materializedComponents()`` is the registry, local and imported
alike). A component defined inside another needed one travels inside it, and one inside
a copied subtree is not repeated, so no id appears twice.

**Definitions are copied as stored.** A carried component is byte-for-byte the subtree
the document holds, never re-positioned or renamed, so a paste can compare it with a
definition the target already holds and reuse it when they are equal.

### Variables and theme axes

A variable is used wherever a string in a root's JSON is `$name` — the rule
``EditableDocument/variableReferences()`` reads by — and the clip follows each one's
value, themed or not, to the variables it references. An axis comes along, with every
option it has, when a carried variable is themed on it or a node or override pins it
with `theme`. A variable or axis nothing in the clip needs stays behind.

### Determinism

The same document and ids always give an equal clip and the same bytes: detached ids are
derived, not drawn, avoiding every id the source and its imports hold; definitions are
ordered by document order, then imported ones by id.

### Not carried

A clip carries no `fonts` declarations — their paths are relative to the source file —
and no `fileToken`. Paste decides where content lands, how ids are regenerated and
what to rename; a clip only describes what was copied.

## Pasting

``PenClip/plan(into:at:)`` reads the target and returns a ``PastePlan`` without writing
anything. Its ``PastePlan/operations`` are applied together, in order — through a
``DocumentSession`` as one ``LocalEdit``, which makes the paste one undo step:

```swift
let clip = try JSONDecoder().decode(PenClip.self, from: pasteboardData)
let plan = try clip.plan(into: session.document, at: .inside(containerID: "Card1"))
try session.submit(.local(LocalEdit(operations: plan.operations)))
select(plan.insertedRootIDs)
```

The operations come in a fixed order: theme axes, then variables, then the component
definitions the target lacks, then the copied roots. ``PastePlan/insertedRootIDs`` names
the copies; the rest of the plan says what was reused and what was renamed.

### Where the copies go

| ``PasteTarget`` | The copies land |
|---|---|
| ``PasteTarget/inside(containerID:)`` | After the container's last child. In a stack they join the flow and lose `x` and `y`; in a free container (a `layout: none` frame or a group) each keeps the offset it had in the parent it was copied out of (``PenClip/Origin/offset``) — or, when that would miss the container's box, they are centered in it |
| ``PasteTarget/after(siblingID:)`` | Right after the node in its parent. In a stack, in the flow; elsewhere to its right, top-aligned, ``PenClip/besideGap`` away (``RootOverlap/margin`` when the node is a root) |
| ``PasteTarget/at(topLeft:in:)`` | The copies' bounds with their top-left corner on the canvas point: into the container, after its last child, or as roots for `nil`. Exact — never moved to fit |
| ``PasteTarget/centered(on:in:)`` | The copies' bounds centered on the canvas point, into the container or as roots. Exact |
| ``PasteTarget/atInnerTopLeft(of:)`` | Into the container, the bounds' top-left corner at its inner top-left (its box moved in by its padding). Exact |
| ``PasteTarget/atBoardOffset(in:)`` | Into the container, each copy at its ``PenClip/Origin/boardOffset`` — its offset from its own board's corner, from the canvas origin for a top-level copy. Exact, even wholly outside the container's box, so a board that clips shows what falls inside it |
| ``PasteTarget/whereCopied(documentID:)`` | Each copy on its own, back where it came from (<doc:Clipboard#Back-where-it-came-from>) |
| ``PasteTarget/inPlace`` | As roots, at the coordinates they were copied from |

Every target that names a container refuses one the document does not store or one that
cannot hold children, and in a stack puts the copies in its flow. The copies keep their
arrangement in every case but ``PasteTarget/atBoardOffset(in:)`` and
``PasteTarget/whereCopied(documentID:)``, which place each by its own origin.

Definitions the target lacks are never put inside a container: they land as roots in a row
past everything on the canvas, ``RootOverlap/margin`` apart — the rule a copied root is
placed by.

Pasted into the free container it was copied out of, a copy lands on its original; pasted
into another, at the same offset there. A copy with no offset — a root copied from the
canvas, or a clip without ``PenClip/origins`` — keeps its canvas position
instead, written in the container's coordinates, and so does every copy of a paste when
any one lacks an offset, so the copies keep their arrangement.

### Back where it came from

``PasteTarget/whereCopied(documentID:)`` places each copied root on its own, so copies
from different parents each go back to theirs (spec §16, the integrator's session 24
ruling):

1. **Copied from the top level**: a root again, at its canvas position. The canvas is in
   every document.
2. **Its parent is here**: when the paste's document id equals the clip's
   ``PenClip/sourceDocumentID`` and the parent is still a frame or group, back into it
   at its offset there — in a stack, in the flow — and at its place: right after its
   source node while that is still there, as Duplicate puts it, else at the index it
   had, clamped to the children there now. Copies from one parent keep their order. A
   copy from the top level keeps its place among the roots the same way when home.
3. **Otherwise** — another document, a parent deleted since, a node drawn inside an
   instance, a clip without origins — at its canvas position, inside the board under its
   center (``EditableDocument/board(at:)``: the top-most top-level frame there), or as a
   root when no board is there.

Which target a gesture means — the selection's board, the board under the pointer, or
back where it came from — is the editor's choice; ``EditableDocument/board(at:)`` gives it
the board under a point by the same rule.

### Sizes

Wherever the copies land, each is sized for its new parent (Penumbra spec §4, Ben's
ruling of 2026-10-15), the rule a move follows
(``EditPlanner/planMove(nodeID:into:at:in:layout:)``): where the parent lays the copy
out — a stack — a dimension that filled its container where it was copied
(``PenClip/Origin/width``, ``PenClip/Origin/height``) fills again; where it does not —
a free frame, a group, the canvas — a dimension still written `fill_container` becomes
the number it was drawn at. `fit_content` works anywhere and stays.

### Ids, names and definitions

**Ids are always new**, drawn to avoid every id the target and its libraries hold, and
every reference in the paste follows: `ref` targets, each segment of a `descendants` key,
a repointed override's `ref`, the nodes of an override's `children`, connection paths.

**A component the target already has is reused** when a target component — its own or an
imported library's — has the same name and the same definition. *Same definition* is
compared after reading both in document-neutral terms (`ComponentFingerprints`):

- node ids are replaced by their pre-order position, so the `Button` a first paste
  brought into a document, under new ids, still equals the source's;
- a component a definition draws is read as that component's own definition, so two
  definitions are equal only when what they draw is equal too;
- a `descendants` key is read as the positions it names in the component it reaches;
- a `$name` is read under the name the paste gives that variable;
- the definition's own `x` and `y` do not count — where it sits is not what it is.

Everything else — every property of every node, the name included — must match. A
component with no name matches by id. When a definition is reused, every instance in the
paste points at the target's, and the instance's override keys are rewritten to the
target's node ids, place by place.

**A component whose name is taken is renamed**: any component the paste inserts — a
carried definition that was not reused, or one of the copies — whose name a target
component has is numbered, `Button` → `Button 2` (`Button 2` → `Button 3`). A copied
component is always a new component, so copying one and pasting it into its own document
gives `Button 2`.

**Variables follow the same rule.** A clip variable the target has (own or imported)
with an equal ``PenVariable`` — type, value and themed variants, with the clip's own
`$references` read under the names the paste gives them — is reused; one that is absent
is added; one whose name holds something else is added renamed, `primary` → `primary-2`,
and every `$primary` in the paste, variables' values included, follows. Because
references count, `$accent: $brand` is reused only when `brand` is too.

**Theme axes** the target lacks are added with the clip's options; an axis of its own
that lacks some is widened, the new options appended so its first option stays its
default. An axis the target reads from a library is left as the library defines it.

### Component loops

A paste into a component — or into anything inside one — that would draw that component
again is refused with ``PasteError/wouldCloseComponentLoop(_:)``, naming the loop from the
component pasted into (`Icon → Button → Icon`, <doc:ComponentLoops>). So is a clip whose
own components draw each other. Nothing is planned, so nothing is written; the loop
guard on every insert would refuse the same operations one by one.

## Topics

### Copying

- ``PenClip``
- ``PenClip/Origin``

### Pasting

- ``PasteTarget``
- ``PastePlan``
- ``EditableDocument/board(at:)``
- ``PasteError``
