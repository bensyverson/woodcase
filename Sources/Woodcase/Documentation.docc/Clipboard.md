# Copying to the Clipboard

A copy takes the selected nodes out of a document as a clip: a .pen that draws on its
own, carrying every component, variable and theme axis those nodes need.

## Overview

An editor's Copy hands ``PenClip/extract(nodeIDs:from:)`` the ids it has selected and
puts the clip's ``PenClip/document`` on the pasteboard; `woodcase clip` prints the same
document. Paste is the other half — a planner that takes a clip into a target document,
reusing what the target already has — and is built separately (Woodcase leaf `kW9xQ1`).
The rules below are the copy half of Penumbra's interaction spec §16 and its session 18
ruling.

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
| A node that was not a root | A root at the canvas position it was drawn at; a `fill_container` width or height becomes the size it was drawn; `layoutPosition` is dropped |
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

## Topics

### Copying

- ``PenClip``
