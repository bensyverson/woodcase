# Planning Edits

Turn "change this property on that node" into the edits that change it — the one planner
the CLI, scripts and editors share.

## Overview

``EditPlanner`` takes an ``EditIntent`` and an address and returns an ``EditPlan`` (the
``EditOperation``s to submit, where they are stored, and the ``WriteDivergence``s the
result will report) or throws an ``EditRefusal`` with a stable ``EditRefusal/Code``.
`woodcase set`, `woodcase override`, a batch's `set` and `override` lines and a script's
`doc.set` all plan through it, so an inspector and an agent produce identical edits for
the same intent, and refuse the same writes.

```swift
let address = NodeAddress("Board/Chip/Label")!
let plan = try EditPlanner.plan(.override(["kind.fills": "#E5484D"]), at: address, in: document)
plan.storage      // .instanceOverride — Label is inside the instance Chip
plan.operations   // [.overrideDescendant(Chi01, Lbl01, ["fill": "#E5484D"])]
try session.submit(.local(LocalEdit(operations: plan.operations)))
```

An editor that already holds a ``ResolvedNodeAddress`` passes it instead of a
``NodeAddress``; the plan is the same. An editor holding an id from the **expanded** tree
gets that address from ``EditableDocument/resolve(expandedID:)`` or
``EditableDocument/inspect(expandedID:)`` — see <doc:InspectingNodes>.

### Intents

| Intent | Plans as |
|---|---|
| ``EditIntent/set(_:)`` | `setProperties` on a node with storage of its own; refused inside an instance |
| ``EditIntent/override(_:unset:)`` | a `descendants` entry, or the instance's root overrides when aimed at the instance itself |
| ``EditIntent/resetOverride(_:)`` | an override that only unsets keys |
| ``EditIntent/bind(property:variable:)`` | a set of `$name`, refused unless the variable exists with the right type |
| ``EditIntent/unbind(property:)`` | a set of the value the bound variable has under the node's theme |

**A set inside an instance is refused; an override is asked for by name.** A write to
a node inside an instance changes that instance only, never the component, and a caller
that reached for `set` — an agent above all — meant to change the node. So
``EditIntent/set(_:)``, ``EditIntent/bind(property:variable:)`` and
``EditIntent/unbind(property:)`` aimed inside an instance throw
``EditRefusal/Code/setInsideInstance``; its ``EditRefusal/suggestion`` is the override's
`key=value` payload (`fill=$brand` for a bind) and its message the exact `override` line or
command. ``EditIntent/override(_:unset:)`` plans that override — property paths translated
to the raw keys the `descendants` map uses, published parameters routed, content the
instance wrote into its own slot written into that slot's fill. Aimed at an instance root,
a set writes the `ref` node's own properties (`common.x`, `common.enabled`); the component
root's properties as the instance shows them are an override.

**A text's sizing mode keeps the size it is drawn at.** `textGrowth` says which of a
text's `fit_content` dimensions follow its words: `auto` both, `fixed-width` the height,
`fixed-width-height` neither. A set or override of it also writes each dimension that stops
following the words as the number it was drawn at — auto to `fixed-width` writes the
width; to `fixed-width-height`, the width and the height — and drops the number of each
that starts following them again (a set removes it, an override writes `fit_content`, to
outweigh the component's). A dimension written in the same edit, or one that fills its
container, is left alone. Without this a text set from auto to fixed width turned 0 wide
(the integrator's ruling of 2026-10-15, Penumbra spec §4.4, leaf `Q2hXKO`). The planner
lays the document out for it, and only for a write that changes `textGrowth`.

### What is refused

| Code | When |
|---|---|
| ``EditRefusal/Code/outOfRange``, ``EditRefusal/Code/offStep`` | a number outside the property's ``PenValueConstraint`` — an opacity of 7, a negative width, a fractional polygon count, a `lineHeight` written in points — or outside a nested key's ``PenNestedShape/Field/constraint``: a gradient stop at position 2, a fill's opacity of 1.5, a negative blur radius |
| ``EditRefusal/Code/undefinedVariable`` | a `$name` the document (and the libraries read with it) does not define; text content alone keeps an undefined `$word` as literal text |
| ``EditRefusal/Code/variableTypeMismatch`` | a `$name` of a type the property does not take — a color bound to an opacity — or, inside a structured value, of a type its nested key does not take: a number variable as a fill's color |
| ``EditRefusal/Code/setInsideInstance`` | a set, bind or unbind aimed inside a component instance; ``EditRefusal/suggestion`` is the override to request instead |
| ``EditRefusal/Code/positionIgnoredByLayout`` | an `x` or `y` on a node its parent's layout places; ``EditRefusal/suggestion`` is the `layoutPosition` write that would honor it |
| ``EditRefusal/Code/storedAtNaturalPath`` | a write names a Woodcase-owned key at its storage path, such as `common.metadata.woodcase.strokeDash`; ``EditRefusal/suggestion`` names its natural path, `kind.strokeDash` (<doc:PenMetadataNamespace>, *Natural paths*) |
| ``EditRefusal/Code/dashOnPerSideStroke`` | a `metadata.woodcase.strokeDash` on a stroke of per-side widths, or per-side widths on a dashed stroke: dashes flow round one outline, which per-side bands are not; ``EditRefusal/suggestion`` removes the dash. A dash itself is held to ``PenStrokeDash``: more than 16 lengths, a negative one or all zeros is ``EditRefusal/Code/outOfRange``, anything but an array of numbers ``EditRefusal/Code/invalidForm`` |
| ``EditRefusal/Code/unknownProperty``, ``EditRefusal/Code/invalidForm`` | a key the node's type lacks, a value of a form it does not take |

Each refusal carries ``EditRefusal/property`` and ``EditRefusal/expected`` — the range
or form that would have been accepted — so an inspector can show it beside the field. For
a value inside a structured one, ``EditRefusal/property`` is still the key written
(`kind.fills`) and the message names the spot (`kind.fills[0].colors[1].position`). The
same spot rides in ``EditRefusal/nested``, a typed ``EditRefusal/NestedLocation`` — here
`[.index(0), .key("colors"), .index(1), .key("position")]`, with
``EditRefusal/NestedLocation/layerIndex`` 0 and ``EditRefusal/NestedLocation/key``
`"position"` — so an inspector places the refusal under the right layer without reading
the sentence; it is `nil` for a refusal about the property itself. What a refusal names
beyond its address and property rides in ``EditRefusal/detail``, an
``EditRefusal/Detail``: the loop a move would close, the component and instances a removal
would orphan, the node and parent of a cycle, or the candidates an address could mean — so
an editor names them in its own words without parsing the sentence or replaying the edit. Only
nested values the write changes are judged: a whole paint list written to edit one layer
passes a value another layer already held, even one out of range.
A value equal to what the node already holds is never refused, so writing back what a
read returned stays a no-op. `woodcase schema` prints every property's constraint.

### Lenient loading

Constraints are a **write** rule, enforced only here. A file holding an opacity of 7
opens; an ``EditOperation`` applied without planning — a three-way merge
(``DocumentMerge``), an undo, a peer's CRDT write — is applied as it is. A merge derived
from a file that loaded must never be refused, which is why the rule lives in the
planner and not in `apply` or `validate`.

### Cross-field checks are lint

A value that is legal on its own but wrong beside another — `fill_container` inside a
`fit_content` parent, a per-side stroke on a shape — is not refused. `woodcase lint`
reports it, and a write rehearsed with `--dry-run` lists the findings it would introduce.

### Group, Frame Selection and Ungroup

Three structural commands keep their geometry here, so an editor, the CLI and an agent
wrap and unwrap nodes the same way (Penumbra's interaction spec §14, the integrator's
ruling of 2026-10-15, which follows Figma). Each returns plain operations to submit as one
edit, and each reads the canvas from a ``PenLayoutState`` of the document as it stands:

```swift
let plan = try EditPlanner.planGroup(nodeIDs: ["a", "b"], kind: .group, named: "Group", in: document, layout: layout)
try session.submit(.local(LocalEdit(operations: plan.operations)))   // then select plan.wrapperID

let operations = try EditPlanner.planUngroup(groupID: plan.wrapperID, in: document, layout: layout)
let several = try EditPlanner.planUngroup(groupIDs: [plan.wrapperID], in: document, layout: layout)
```

- ``EditPlanner/planGroup(nodeIDs:kind:named:in:layout:)`` wraps the top-most members (a member
  inside another is dropped, not refused) in a group or a free frame (``WrapKind``). The
  wrapper goes into the parent of the front-most member — the last in document order — at
  that member's index; members from other parents move in, in document order. In a stack
  the wrapper takes that member's place in the flow, and the members become its free
  children where they were drawn. A name given rides the wrapper. When the front-most
  member is in an instance's slot content, the wrapper goes into that slot's fill and the
  whole change is one override of the slot (<doc:SlotEditing>); a stored front-most member
  with slot content among the others is refused.
- ``EditPlanner/planUngroup(groupID:in:layout:)`` moves a group's or a frame's children to
  its parent at its index, in their order, and removes it. In a stack they join the flow.
  A connector attached to the group or frame itself would be left naming nothing, so it is
  deleted first, in the same edit, as a delete takes one; the connectors attached to the
  children stay (the integrator's ruling of 2026-10-23).
- ``EditPlanner/planUngroup(groupIDs:in:layout:)`` takes several apart as one edit: stored
  ones front to back, as the one-group plan plans each, and ones in slot content in their
  fills, each slot written once, with ``StructuralEditPlan/placedIDs`` naming the children.

**Nothing moves on the canvas.** A node placed by its own `x`/`y` is drawn by
`translate(x, y) · turn · flip` about its anchor in its parent's own coordinates, so each
moved node's new local map is its new parent's canvas map inverted, after its old canvas
map; that map is read back as an anchor, a turn and flips. Pen has no scale, so the
reading always exists. A turn or flip changes only when the new parent's chain turns or
flips differently from the old one; flips follow the chain's parity (a child of a
`flipY` group keeps `flipY` when ungrouped, with the group's turn added to its own). A
`fill_container` size is frozen at the size it was drawn at when the new parent does not
lay the node out — a group or free frame, or a stack holding it absolutely — because a fill
there has nothing to fill; children ungrouped into a stack's flow keep their fill, which
the stack lays out (see Moving a node below).

**The wrapper is unturned in its parent.** It spans the union of its members' canvas
quads, measured in its parent's own coordinates: a group's box is that union, and a frame
is placed and sized to it with `layout: none`, no fill and no clip, so wrapping draws
nothing new. Under a turned parent the union is the parent's axis-aligned box of the turned
members — turning the wrapper to fit one member would turn the others with it.

Two limits, both the flow's rather than the planner's: grouping in a stack keeps every
member where it was only when the members sit together in the flow, since the wrapper
takes one slot; and an ungroup into a stack places the children by the flow, which keeps
them where they were only when they sat as the flow would put them. A hidden child of a
stack has no place of its own, so it keeps what it stored.

| Code | When |
|---|---|
| ``EditRefusal/Code/noNodes`` | the list is empty |
| ``EditRefusal/Code/insideInstance`` | a member, or the group, is inside a component instance or a slot's content |
| ``EditRefusal/Code/notAGroup`` | an ungroup aimed at a node that is neither a group nor a frame |
| ``EditRefusal/Code/addressNotFound`` | an id names no node |
| ``EditRefusal/Code/wouldCloseComponentLoop`` | a member moving in would make a component contain itself; ``EditRefusal/detail`` is the loop (``EditRefusal/Detail/componentLoop(_:)``), named, in render order from the component written into |
| ``EditRefusal/Code/componentHasInstances`` | the frame ungrouped is a component with instances; ``EditRefusal/detail`` names the component and its instances |

Lock has no planner of its own: it is a set of `common.locked`, stored in
`metadata.woodcase.locked` (``PenMetadata/WoodcaseKey/locked``), planned as any other set, and ``PenNode/isLocked``
reads it back; see <doc:PenMetadataNamespace>.

### Deleting a node

Deleting a node also deletes every connector attached to it or to anything inside it, in
the same edit, so no connector is left pointing at a node that no longer exists — Pen's
format has no free end (Ben's ruling of 2026-10-23, Penumbra's interaction spec §11).
``EditPlanner/planDelete(nodeIDs:in:)`` is the one place that decides it: Delete and Cut in
an editor, `woodcase rm`, a batch's `rm` line and a script's remove all plan through it.

```swift
let plan = try EditPlanner.planDelete(nodeIDs: ["Card"], in: document)
plan.connectorIDs    // the connectors that end on Card or inside it, in document order
try session.submit(.local(LocalEdit(operations: plan.operations)))
```

A connector end is attached to a deleted node when any id its path names is one: the node,
a node inside it, an instance inside it (`Chip/Label` goes with `Chip`), or a component's
own node that an instance shows (`Chip/Label` goes with `Label` too). The plan
(``DeletionPlan``) deletes the connectors first and then the nodes, so the undo — one step,
the reverse — puts the nodes back before the connectors that name them, each where it was.
Each id is deleted once: a node inside another given node goes with it, and a connector
that is itself being deleted is not taken again. An id inside a component instance is
refused (``EditRefusal/Code/insideInstance``), and one naming nothing
(``EditRefusal/Code/addressNotFound``).

`woodcase rm --detach` detaches a component's instances before it deletes the component,
and a detach rewrites the connector ends into an instance to the detached copy (see
<doc:EditingDocuments>), so the connectors into those instances (`Chip/Label`) stay; only an
end still naming a removed node takes its connector.

A batch `replace` that drops nodes from the subtree it rewrites takes their connectors the
same way. Both answers name what went, as a ``WriteDivergence/Kind/deletedConnectors``
note: `removing Card also removed 2 connectors that ended on it or inside it: Flow, Link`.

Ungroup is not a delete of its children: they keep their ids and their connectors. The
wrapper it removes does take its own connectors, as a delete would.

### Connectors a copy carries

Copy, and so Cut, carries every connector whose two ends are both inside the copied nodes
— a copied node or anything inside it — whether or not the connector was selected; a
connector with one end outside the copy stays behind (Ben's ruling of 2026-10-23,
Penumbra's interaction spec §11). Duplicate and an Option-drag copy
(``EditPlanner/planDuplicate(nodeIDs:in:)``, whose copies are named in
``StructuralEditPlan/carriedConnectorIDs``) and `woodcase cp` follow the same rule, so it
lives in one query:

```swift
let carried = EditPlanner.connectorIDs(enclosedBy: ["CardA", "CardB"], in: document)
// ["KAB"]: both its ends are inside the copy; one from CardA to CardC is not carried
```

An end is inside the copy when its path's first id is a copied stored node or a node inside
one (`Chip/Label` is inside a copied `Chip`), or when it is the expanded id of a copied node
drawn inside an instance, or of anything drawn inside that — an instance drawn there
included under the path an end names it by (`Filled/Row2`, not `Filled/Row2/ItemB`). A connector among the copied
nodes is not listed: it is copied already. ``PenClip/extract(nodeIDs:from:documentID:)``
asks this (<doc:Clipboard>); its counterpart for a removal is
``EditPlanner/connectorIDs(attachedTo:in:)``.

### The default text style

A document's default text style is a text marked with `metadata.woodcase.defaultTextStyle:
true` (``PenMetadata/WoodcaseKey/defaultTextStyle``), and the default is that text's live
style: restyle it and the default follows (Penumbra spec §6.3, Ben's ruling of 2026-10-18).
The format has no document-level metadata, and Pen keeps a node's.

```swift
let operations = try EditPlanner.planMarkDefaultTextStyle(nodeID: id, in: document)
try session.submit(.local(LocalEdit(operations: operations)))   // one undo step

document.defaultTextStyleNodeID()        // the first marked text in document order
document.firstFontFamilyVariableName()   // e.g. "body": bind a new text's family to "$body"
```

- ``EditPlanner/planMarkDefaultTextStyle(nodeID:in:)`` marks one text and takes the mark
  off every other text that holds it, as plain property writes for one edit; each write
  folds the one key onto the node's metadata, so the rest is kept. Marking the only marked
  text plans nothing. It is refused for a node that is not a text
  (``EditRefusal/Code/notAText``), inside a component instance
  (``EditRefusal/Code/insideInstance``), and for an id naming nothing
  (``EditRefusal/Code/addressNotFound``).
- ``EditPlanner/planUnmarkDefaultTextStyle(in:)`` takes every mark off — what choosing the
  command on the current default does — so a second mark cannot quietly take over.
- ``EditableDocument/defaultTextStyleNodeID()`` is the first marked text in document order
  (``EditableDocument/nodeIDsInDocumentOrder()``), so two marks after a merge or a paste
  resolve the same way on every peer.
- ``EditableDocument/firstFontFamilyVariableName()`` is the first string variable, by name,
  that some text binds as its `fontFamily` — the fallback when no text is marked. It is
  never guessed from a variable's name or value.

### Moving a node

``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)`` plans a move to another parent: the
`moveNode`, then — when the new parent does not lay the node out — each `fill_container`
width or height written as the number it was drawn at; a `fit_content` one stays (Ben's
ruling of 2026-10-15, Penumbra spec §4.4, leaf `skbh2k`, as Figma does). A stack lays a
child out on both axes — a share of the main axis, the cross axis stretched — so the check
is per parent, not per axis: a frame with a layout lays out a child it holds in flow; a
free frame, a group, the canvas, and a stack's absolutely positioned child get no room
on either axis, and a fill there settles at its fallback or content, often zero. The CLI's
`mv` and a batch's `mv` line plan the same sizes. A caller that drops the node at a point
writes its `x`/`y` after these edits. A move is refused inside an instance, for an id naming
nothing, with ``EditRefusal/Code/wouldCreateCycle`` when the parent is the node or inside it,
and with ``EditRefusal/Code/wouldCloseComponentLoop`` when it would make a component
contain itself; either way ``EditRefusal/detail`` names what it found.

```swift
var operations = try EditPlanner.planMove(nodeID: "row1", into: "board", in: document, layout: layout)
operations.append(.setProperties(EditOperation.SetProperties(nodeID: "row1", properties: ["common.x": 40, "common.y": 20])))
```

A drop that should land where the pointer carried the node — Penumbra's free reparent —
passes `keepingDrawnPlace:` the canvas offset instead of writing `x`/`y` itself. Where the
new parent places the node by position (a free frame, a group, the canvas, or a stack
holding it `absolute`), the planner then rewrites its `x`/`y`, rotation and flips together
with the same placement Group and Ungroup use, so its quad on the canvas is the one it was
drawn as, moved by the offset. A turn is not carried as "old turn plus the difference of the
parents' turns": a flipped parent reverses the sense of its child's turn, so moving into
one toggles the node's flip and mirrors its turn. A child a stack takes into its flow is
placed by the stack, and the offset changes nothing (issue `qIds8z`, leaf `XOP0ZQ`).

```swift
let operations = try EditPlanner.planMove(
    nodeID: "chip", into: "turnedBoard", keepingDrawnPlace: PenPoint(x: 120, y: -40), in: document, layout: layout
)
```

Pass `snapping: .wholePoints` (``PlacementSnapping``) to land the drop on whole points, as a
plain move does: the node's new `x`/`y` are rounded in the new parent's space before they are
compared with the stored ones, so a stored fractional coordinate the move would leave in
place is written rounded too. Rotation and flips are never snapped.

A node in an instance's slot, or a slot as the new parent, is planned by
``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)``, as one
`children` override of each slot it touches; the single-node planner refuses slots. See
<doc:SlotEditing>.

A paste needs no rule of its own: a clip already freezes a fill size at the size it was
drawn at when it copies a node out of its parent (``PenClip``).

### Scaling

Scale multiplies a selection by one factor about an anchor point, proportionally only, so
no font is ever stretched (Penumbra spec §5, Ben's rulings of 2026-10-14 and 2026-10-18;
the design and its two-way doors are in `project/2026-10-19-proportional-scale.md`). A live
gesture captures the selection once and plans each step from that capture, so factors never
compound; a one-off scale plans in one call.

```swift
let capture = try ScaleCapture(nodeIDs: selection, in: document, layout: layout)   // at the press
let step = try capture.plan(factor: 1.4, around: pivot, in: document)              // every frame
let drawn = try document.previewNodes(for: step.operations)
try session.submit(.local(LocalEdit(operations: step.operations)))                 // on release

let plan = try EditPlanner.planScale(nodeIDs: selection, by: 0.5, anchor: .center, in: document, layout: layout)
plan.unscaled   // [BoundValue(nodeID: "Card", property: "kind.gap", variable: "space")]
```

- **What scales**, on the node and every descendant: a member's position about the anchor
  and a descendant's in its parent; fixed widths and heights, and the fallback in
  `fit_content(n)`; `fontSize` (as drawn, so an unset one is written as 16 × the factor),
  `letterSpacing` and each rich-text run's size; `strokeWidth`, uniform or per side, and
  the dash and its offset; `cornerRadius`, `gap`, `padding`; a shadow's offset, blur and
  spread (the spread's shadow snapshot too, so it stays fresh), a layer blur's and a
  background blur's radius. A note, prompt or context scales its box and its type size.
- **What does not**: sizing modes (an `auto` text keeps fitting its words, a
  `fill_container` keeps filling), `lineHeight` (a multiple of the size here), path
  geometry (drawn into the box), rotation, flips, opacity and fills. A value bound to a
  variable stays bound and is listed in ``ScalePlan/unscaled``.
- **Where it moves things**: a member placed by its own `x`/`y` lands where the scale about
  the canvas anchor sends it, under a turned or flipped parent too; a member a stack places
  grows in its slot. ``ScaleAnchor`` names the nine points of ``ScaleCapture/bounds``, the
  members' canvas union. Lengths keep two decimals and a note's look scale four, never
  rounded to nothing (``PenScaleRounding``, which an editor that sizes a note another way
  rounds through too).
- **Where it writes**: as ``EditPlanner/routeWrites(_:at:in:)`` routes every gesture's
  values (below): a node with storage of its own takes one `setProperties`; inside an
  instance every write is an override on the instance, and the component is unchanged. An
  instance root's `x`/`y` are its own and the rest are root overrides. A factor of 1 plans nothing; one that is not positive and finite is
  ``EditRefusal/Code/outOfRange``.

### Routing a gesture's writes

A canvas gesture — a move, a resize, a turn, a scale — computes the values it wants a node
drawn with, not where the format keeps them. ``EditPlanner/routeWrites(_:at:in:)`` makes
that decision once, for every editor and for ``ScaleCapture``:

| Target | Where the values go |
|---|---|
| a node with storage of its own | one `setProperties` on the node |
| an instance root (a `ref` node) | its `common.` properties on the `ref`; the rest as root overrides |
| a node inside an instance, a nested instance's root among them | an override on the outermost instance |

Own writes are not planned — the values are ones the node already draws, moved, sized or
turned, and a live gesture runs this every display refresh — though a deep metadata key is
still folded. Every override is planned, so its refusals hold: an `x` on a node its
instance's layout places throws ``EditRefusal``, which an editor shows rather than drops.

```swift
// Chip is an instance: x is the ref's own, width a root override.
let operations = try EditPlanner.routeWrites(["common.x": 40, "kind.width": 240], at: .node(id: "Chip"), in: document)
```

### Routing an inspector's intent

An inspector changes a value, binds a variable or unbinds one, where the node it shows is
stored however it is. ``EditPlanner/plan(_:routedAt:in:)`` plans an ``EditIntent`` by the
same rule ``EditPlanner/routeWrites(_:at:in:)`` follows (one internal decision, so the two
and ``NodeInspection/storage(of:)`` cannot drift): a set is split between the node's own
storage and the instance's overrides, a bind of an overridden property becomes an override
of `$name` — still refused for a missing variable or one of the wrong type — and an unbind
becomes an override of the value the variable the instance shows resolves to, under the
node's theme. Content an instance wrote into its slot is written into the slot's fill, where
a plain set is refused. An inspector that asked for the override by showing the instance
uses this; a CLI or script that did not ask keeps ``EditPlanner/plan(_:at:in:)-(_,ResolvedNodeAddress,_)``,
which refuses a set inside an instance (leaf `OYvGo2`, Penumbra issue `S5Q58m`).

```swift
// Chip is an instance: x is the ref's own, the fill a root override.
let plan = try EditPlanner.plan(.set(["common.x": 80, "kind.fills": "#E5484D"]), routedAt: .node(id: "Chip"), in: document)
let detach = try EditPlanner.plan(.unbind(property: "kind.fills"), routedAt: inspection.address, in: document)
```

### Previewing a plan

An editor shows a gesture in progress (a scrubbed value, a dragged gradient stop, a
number being typed) on its own canvas before committing it, without sending each step
to collaborators, the undo stack or the file. It plans each step as above, and hands the
plan's operations to ``EditableDocument/previewNodes(for:)``. That returns the stored
nodes a commit would leave, using the commit's own normalization
(``EditOperation/normalized(in:)``, so a deep metadata key such as
`common.metadata.woodcase.fontSize` folds onto the node's metadata as it does on a commit),
patch and override code, and changes nothing. ``EditableDocument/materializeSnapshot(overlaying:isolation:)`` then draws the
document with those nodes swapped in. A plan's operations are always property edits, as is a whole-struct
`updateCommon` or `updateKind` that normalizes to one; any other operation throws ``EditableDocument/PreviewError/notAPropertyEdit(_:)``.

```swift
let plan = try EditPlanner.plan(.set(["common.opacity": 0.4]), at: address, in: document)
let preview = try document.previewNodes(for: plan.operations)
let drawn = await document.materializeSnapshot(overlaying: preview)
```

## Topics

### Planning

- ``EditPlanner``
- ``EditIntent``
- ``EditPlan``
- ``EditPlanner/plan(_:routedAt:in:)``
- ``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)``
- ``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)``
- ``StructuralEditPlan``
- <doc:SlotEditing>
- ``EditPlanner/planGroup(nodeIDs:kind:named:in:layout:)``
- ``EditPlanner/planUngroup(groupID:in:layout:)``
- ``EditPlanner/planUngroup(groupIDs:in:layout:)``
- ``EditPlanner/planDelete(nodeIDs:in:)``
- ``DeletionPlan``
- ``EditPlanner/connectorIDs(attachedTo:in:)``
- ``EditPlanner/connectorIDs(enclosedBy:in:)``
- ``EditPlanner/planScale(nodeIDs:by:anchor:in:layout:)``
- ``EditPlanner/planMarkDefaultTextStyle(nodeID:in:)``
- ``EditPlanner/planUnmarkDefaultTextStyle(in:)``
- ``EditableDocument/defaultTextStyleNodeID()``
- ``EditableDocument/firstFontFamilyVariableName()``
- ``WrapKind``
- ``WrapPlan``

### Scaling

- ``ScaleCapture``
- ``ScalePlan``
- ``ScaleAnchor``
- ``PenScaleRounding``

### Previewing

- ``EditableDocument/previewNodes(for:)``
- ``EditableDocument/PreviewError``
- ``EditableDocument/materializeSnapshot(overlaying:isolation:)``

### Refusals

- ``EditRefusal``
- ``PenValueConstraint``

### Inspecting

- <doc:InspectingNodes>
