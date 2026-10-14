# Copy and Paste

A copy takes the selected nodes out of a document as a clip: a .pen that draws on its
own, carrying every component, variable and theme axis those nodes need. A paste plans
taking a clip into a document, reusing what the document already has.

## Overview

An editor's Copy hands ``PenClip/extract(nodeIDs:from:)`` the ids it has selected and
puts the clip's ``PenClip/document`` on the pasteboard; `woodcase clip` prints the same
document. Paste is the other half: ``PenClip/plan(into:at:)`` takes a clip and a target
document and returns the operations that bring it in (<doc:Clipboard#Pasting>); `woodcase paste`
applies them to a file. The rules below are Penumbra's interaction spec §16 and its
session 18 ruling.

```swift
let clip = try PenClip.extract(nodeIDs: selection, from: document)
pasteboard.setData(try PenParser.encodeForFile(clip.document), forType: penType)
```

### What a clip holds

The clip's roots are the copied subtrees first, named by ``PenClip/contentIDs`` in
document order, then the component definitions carried along for them. Its `variables`
and `themes` hold exactly what those roots need, and it has no `imports`.

| Copied | Comes out as |
|---|---|
| A stored node | Its subtree as stored, ids unchanged — unless it was copied out of a component the clip also carries, which would hold it twice; then it takes derived ids of its own |
| A node under another copied node | Nothing more: it travels inside the outer one |
| A node that was not a root | A root at the canvas position it was drawn at; a `fill_container` width or height becomes the size it was drawn; `layoutPosition` is dropped. Its offset in its parent — the point its `x` and `y` named there, as drawn, so a stack child records where the stack put it — goes in ``PenClip/offsets`` |
| An instance (a `ref`, or its expanded root id) | The `ref`, still linked, with its component carried |
| A node inside an instance | Its drawing — overrides applied, nested instances expanded — detached, under ids derived as a detach derives them (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``) |
| A component from an imported library | A local definition under its prefixed id (`K:Chip1`), with the library variables it uses (`$K:accent`) |

The ids ``PenClip/extract(nodeIDs:from:)`` takes are the expanded document's — the ones
a canvas selects and hit-tests (``EditableDocument/expandedID(of:)``) — and a stored
node's own id is accepted as well. A position is the canvas point a root's `x` and `y`
name, its own origin: a node keeps its own turn, but a turn it inherited from an
ancestor is not carried.

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
| ``PasteTarget/inside(containerID:)`` | After the container's last child. In a stack they join the flow and lose `x` and `y`; in a free container (a `layout: none` frame or a group) each keeps the offset it had in the parent it was copied out of (``PenClip/offsets``) — or, when that would miss the container's box, they are centered in it |
| ``PasteTarget/after(siblingID:)`` | Right after the node in its parent. In a stack, in the flow; elsewhere to its right, top-aligned, ``PenClip/besideGap`` away (``RootOverlap/margin`` when the node is a root) |
| ``PasteTarget/canvas(center:)`` | As roots, the clip's bounds centered on the point |
| ``PasteTarget/inPlace`` | As roots, at the coordinates they were copied from |

Definitions the target lacks are never put inside a container: they land as roots in a row
past everything on the canvas, ``RootOverlap/margin`` apart — the rule a copied root is
placed by.

Pasted into the free container it was copied out of, a copy lands on its original; pasted
into another, at the same offset there. A copy with no offset — a root copied from the
canvas, or a clip written before ``PenClip/offsets`` existed — keeps its canvas position
instead, written in the container's coordinates, and so does every copy of a paste when
any one lacks an offset, so the copies keep their arrangement.

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

### Pasting

- ``PasteTarget``
- ``PastePlan``
- ``PasteError``
