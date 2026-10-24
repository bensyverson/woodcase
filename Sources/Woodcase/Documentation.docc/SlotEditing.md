# Slot Editing

Read an instance's slots, and plan structural edits inside them: move, insert, delete,
duplicate, replace, empty, reset, and swap the instance itself.

## Overview

A **slot** is a frame inside a component with `slot` set; its list names the components it
**suggests**, which never restricts what goes in. An instance fills a slot by storing the
slot's whole content as one `children` override of the slot frame — its **fill**. Everything
in a fill belongs to the instance, so a slot is edited like any frame (Penumbra spec §13.5),
and every structural change to it is written as **one `children` override of the slot**:
recorded, replicated and undone as one value.

### Reading slots

``EditableDocument/slots(ofInstance:)``, ``EditableDocument/slot(_:)`` and
``EditableDocument/slot(containing:)`` answer with ``InstanceSlot``: the slot frame's expanded
id, the instance that shows it, the stored `ref` node that holds its fill, its state
(``InstanceSlot/State/default``, ``InstanceSlot/State/filled`` or
``InstanceSlot/State/empty``), its content's expanded ids and its suggested components by
name.

```swift
let list = document.slot("Filled/List")
list?.state         // .filled
list?.contentIDs    // ["Filled/Row1/ItemA", "Filled/Row2/ItemB", "Filled/Row3/ItemA"]
```

``EditableDocument/acceptsChildren(_:)`` is the drop-target question: inside an instance
only a slot frame — at any depth — or a frame or group in a slot's content takes children.
``EditableDocument/componentLoop(moving:under:)`` and
``EditableDocument/componentLoop(inserting:under:)`` take a slot as the parent too.

### Where a fill is stored

A slot of the component an instance places, or of an instance nested in that component,
is a key of the outermost instance's `descendants` map (`List`, `PScr/List`). A slot of an
instance placed *inside a fill* is not: Pen lets no key of the outer instance reach content
it wrote itself (`project/2026-09-26-slot-override-keys.md`, rule 5), so that fill lives in
the inner instance's own JSON, inside the outer fill, and the write is one override of the
outer slot carrying it. Either way ``InstanceSlot/refID`` is the stored node written.

The reads and the planners walk the instance as ``PenRefExpander`` prepares it, one level
of nesting at a time, so a slot's content is exactly what is drawn: the fill, or the
default content with the instance's overrides folded in.

### Planning structural edits

- ``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)`` moves nodes
  into, within and out of slots, and anywhere outside instances. A node moved in from the
  document leaves its parent (its attached connectors go with it); one moved out becomes an
  ordinary node. Several nodes write each slot once. The single-node
  ``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)`` still refuses
  slots, so a caller that plans node by node and concatenates can't write a slot from a
  stale copy.
- ``EditPlanner/planInsert(_:into:at:in:)`` places new or pasted nodes;
  ``EditPlanner/planDuplicate(nodeIDs:in:)`` copies nodes after themselves;
  ``EditPlanner/planDelete(nodeIDs:in:)`` deletes slot content from its fill.
- ``EditPlanner/planReplaceSlotContent(slotID:with:count:in:)`` replaces the content with
  instances of a component — as many as it had layers, at least one;
  ``EditPlanner/planEmptySlot(slotID:in:)`` leaves it empty, which is not its default;
  ``EditPlanner/planResetSlot(slotID:in:)`` removes the fill.
- ``EditPlanner/planSwap(instanceID:to:in:)`` swaps an instance's component, each fill moving
  to the new component's slot of the same name and the rest dropped and reported
  (``SwapPlan``).
- ``EditPlanner/planMakeSlot(frameID:in:)``, ``EditPlanner/planSuggestedComponents(_:frameID:in:)``
  and ``EditPlanner/planRemoveSlot(frameID:in:)`` author slots in a component;
  ``SlotRemovalPlan`` names the instances whose fills Remove Slot clears.

Outside slots the instance rules stand: a node of an instance's component is refused with
``EditRefusal/Code/insideInstance``, and a loop through ``EditRefusal/Code/wouldCloseComponentLoop``.

### The first change copies the default

While a slot shows its component's default content, those nodes are the component's. The
first structural change on that slot copies the content — its overrides folded in — into a
fill, then applies the change, in the same plan (spec §13.5 rule 6). The copies take fresh
ids, and the keys that named the default content are removed, since nothing they name is
drawn any more. ``StructuralEditPlan/renamedIDs`` and ``StructuralEditPlan/renamed(_:)``
carry a selection across, and ``StructuralEditPlan/materializedSlotIDs`` names the slots
copied.

```swift
let plan = try EditPlanner.planMove(nodeIDs: ["Loose"], into: "Default/List", at: 0, in: document, layout: layout)
plan.materializedSlotIDs                      // ["Default/List"]
plan.renamed("Default/Empty1/EmptyState")     // "Default/k3Fq9/EmptyState"
```

### Ids stay unique

Pen renames a repeated id on load, a node in a fill included, and a path to it stops
resolving (rule 6 of the slot-override-keys finding). So every copy headed into a fill — a
duplicate, a Replace, the default content's first copy — takes fresh ids at every depth, the
nodes in its instances' fills included; a node moved or inserted keeps its ids only when no
node anywhere has them (``EditableDocument`` counts fills as in use). `woodcase cp` and
``EditPlanner/planDuplicate(nodeIDs:in:)`` renumber a copied instance's fills the same way.

## Topics

### Reading

- ``InstanceSlot``
- ``EditableDocument/slots(ofInstance:)``
- ``EditableDocument/slot(_:)``
- ``EditableDocument/slot(containing:)``
- ``EditableDocument/acceptsChildren(_:)``

### Planning

- ``StructuralEditPlan``
- ``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)``
- ``EditPlanner/planInsert(_:into:at:in:)``
- ``EditPlanner/planDuplicate(nodeIDs:in:)``
- ``EditPlanner/planReplaceSlotContent(slotID:with:count:in:)``
- ``EditPlanner/planEmptySlot(slotID:in:)``
- ``EditPlanner/planResetSlot(slotID:in:)``
- ``EditPlanner/planSwap(instanceID:to:in:)``
- ``SwapPlan``

### Authoring

- ``EditPlanner/planMakeSlot(frameID:in:)``
- ``EditPlanner/planSuggestedComponents(_:frameID:in:)``
- ``EditPlanner/planRemoveSlot(frameID:in:)``
- ``SlotRemovalPlan``
