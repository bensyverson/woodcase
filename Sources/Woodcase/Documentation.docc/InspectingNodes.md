# Inspecting Nodes

What an inspector reads before it shows a control: the fields a node type takes, the
address an expanded node answers to, what it overrides, and the variables a field may bind.

## Overview

An editor builds its inspector from Woodcase rather than from its own copy of the format,
and writes every change through ``EditPlanner``. Four queries feed it, each one call:

| Question | Call | Answer |
|---|---|---|
| Which fields does this type take, and what shape is each? | ``PenSchema/fields(for:)``, ``PenSchema/field(_:for:)`` | ``PenSchemaTable/Property`` rows |
| Which address edits this node of the expanded tree? | ``EditableDocument/resolve(expandedID:)`` | ``ResolvedNodeAddress`` |
| Where do its values come from, and which does this instance override? | ``EditableDocument/inspect(expandedID:)`` | ``NodeInspection`` |
| Which variables may bind to this field? | ``EditableDocument/bindableVariables(for:at:)`` | ``BindableVariable`` list |

```swift
let inspection = document.inspect(expandedID: "Card1/Btn02/Lbl02")!
inspection.address           // .instanceDescendant(refID: "Card1", descendantKey: "Btn02/Lbl02")
inspection.source            // .componentNode(definitionID: "Lbl02")
inspection.overriddenPaths   // ["kind.content"]

let colors = document.bindableVariables(for: "kind.fills", at: inspection.address)
colors.map(\.name)           // ["brand", "ink"] — only color variables

let plan = try EditPlanner.plan(.override(["kind.fills": "$brand"]), at: inspection.address, in: document)
```

### Fields

``PenSchema/fields(for:)`` is the `common.*` table and the type's own `kind.*` table in
one list — the rows `woodcase schema` prints, assembled from the decoders, so a control
cannot drift from the format. A row carries everything a control needs: the
``PenSchemaTable/Property/path`` it writes, the ``PenSchemaTable/Property/spellings`` a
picker offers, the ``PenSchemaTable/Property/constraint`` a number field keeps to (the
planner refuses outside it), the ``PenSchemaTable/Property/variable`` type a binding must
have, and the ``PenSchemaTable/Property/nested`` key tables of a fill, an effect or a
stroke width. ``PenSchema/field(_:for:)`` finds one row by path or by raw key.

### Expanded ids

The layout engine, the renderer and the hit test run on the **expanded** document, where
an instance root is `<ref id>/<component root id>` and a node inside it
`<ref id>/<descendants key>`. ``EditableDocument/resolve(expandedID:)`` is the inverse of
``EditableDocument/expandedID(of:)``: it resolves each candidate reading as an id-only
address and keeps the one that maps back to the same id, so the two directions cannot
disagree. A ref's bare id is not in the expanded tree, and maps to nothing.

### Override state

``NodeInspection/source`` says where a node's stored values live:

| Source | The node | Its overrides |
|---|---|---|
| ``NodeInspection/Source/ownStorage`` | a node with storage of its own | none; edit with ``EditIntent/set(_:)`` |
| ``NodeInspection/Source/instance(componentID:)`` | an instance root | the root overrides it stores |
| ``NodeInspection/Source/componentNode(definitionID:)`` | a component's node, shown through an instance | its entry in the outermost instance's `descendants` map |
| ``NodeInspection/Source/slotContent`` | content the instance wrote into a slot | none; it is written where it is |

``NodeInspection/overrides`` lists what **this** instance stores — raw key, the property
path a field row carries (`nil` for a key that is no property, such as a slot's
`children`), and the value. An override a component's own nested instance stores belongs
to that component. ``NodeInspection/sourceNode`` is the node as stored before this
instance's overrides, and its id is the definition to navigate to.

A set aimed inside an instance is refused (``EditRefusal/Code/setInsideInstance``), so an
inspector writes a field of a ``NodeInspection/Source/componentNode(definitionID:)`` or
an instance root's component properties with ``EditIntent/override(_:unset:)``, and resets
one with ``EditIntent/resetOverride(_:)`` passing ``NodeInspection/overriddenPaths``.

### Bindable variables

``EditableDocument/bindableVariables(for:at:)`` lists the variables of exactly the type
the field binds — from the document and from the libraries read with it, each with its
``BindableVariable/origin`` — so every one plans as a binding. Each carries its value under
the theme the node draws with, the value ``EditIntent/unbind(property:)`` would write.

## Topics

### Queries

- ``EditableDocument/resolve(expandedID:)``
- ``EditableDocument/inspect(expandedID:)``
- ``EditableDocument/inspect(_:)``
- ``EditableDocument/bindableVariables(for:at:)``
- ``PenSchema/fields(for:)``
- ``PenSchema/field(_:for:)``

### Results

- ``NodeInspection``
- ``BindableVariable``
