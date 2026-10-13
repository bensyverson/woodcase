# Inspecting Nodes

What an inspector reads before it shows a control: the fields a node type takes, the
address an expanded node answers to, what it overrides, and the variables a field may bind.

## Overview

An editor builds its inspector from Woodcase rather than from its own copy of the format,
and writes every change through ``EditPlanner``. Five queries feed it, each one call:

| Question | Call | Answer |
|---|---|---|
| Which fields does this type take, and what shape is each? | ``PenSchema/fields(for:)``, ``PenSchema/field(_:for:)`` | ``PenSchemaTable/Property`` rows |
| Which address edits this node of the expanded tree? | ``EditableDocument/resolve(expandedID:)`` | ``ResolvedNodeAddress`` |
| Where do its values come from, and which does this instance override? | ``EditableDocument/inspect(expandedID:)`` | ``NodeInspection`` |
| Which variables may bind to this field? | ``EditableDocument/bindableVariables(for:at:)``, ``EditableDocument/bindableVariables(ofType:at:)`` | ``BindableVariable`` list |
| Which fonts can a text be set in? | ``PenFontRegistry/availableFamilies(cache:)``, ``PenFontRegistry/faces(of:cache:)`` | family names, ``PenFontFace`` list |

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

A row also says what the property is when a node leaves it unset:
``PenSchemaTable/Property/default`` is the value the layout engine and the renderer use in
its place (``PenPropertyDefault``) — `"horizontal"` for a frame's `layout`, 16 for a
text's `fontSize` and 13 for a note's, `"fit_content"` for a width — so a control shows the
value the canvas draws rather than an empty field, and an "add" that writes it changes
nothing. A text's `lineHeight` and `letterSpacing` have no number: they come from the font
(``PenPropertyDefault/Derivation``). A property where unset draws nothing (`fills`) has no
default. `PenSchemaDefaultEngineTests` draws every literal default against the property
left unset, so the schema cannot name a value the engine does not use. `woodcase schema
<type>` prints them in a DEFAULTS section, and its JSON (``SchemaPropertyReport``) carries
`default` (the literal) or `defaultFrom` (where a derived one comes from); each nested key's
constraint rides on ``SchemaNestedReport/Field/constraint`` and ends its line in the text.

A nested key carries a default the same way (``PenNestedShape/Field/default``): a gradient's
unset `center` is `{x: 0.5, y: 0.5}` and its `size` `{width: 1, height: 1}`, its `rotation`
is 0, and a paint's `enabled`, `blendMode` and `opacity` are `true`, `"normal"` and 1; a
shadow's `shadowType` is `"outer"`, and a per-side stroke width left out is 0. The text
ends the key's line with `— default 0.5`; the JSON carries
``SchemaNestedReport/Field/default``. `PenNestedDefaultEngineTests` draws each with the key
unset and with the default written and requires the same pixels, so the table cannot name
a value the renderer does not use. A shader fill's keys state none: the CoreGraphics
renderer draws no shader, so nothing pins them.

The typography strings carry a role of their own, so a control is chosen by the form a
row takes rather than by its path: ``PenValueForm/StringRole/fontFamily`` (a menu of
``PenFontRegistry/availableFamilies(cache:)``), ``PenValueForm/StringRole/fontWeight``
and ``PenValueForm/StringRole/fontStyle``, whose ``PenValueForm/StringRole/keywords``
list the words each reads (`"bold"`, `"italic"`).

### Fonts

``PenFontRegistry/availableFamilies(cache:)`` lists every family Woodcase can set a text
in: what Core Text has, the system's and every family registered in this process, and
what the Google Fonts cache holds and a read would register from disk. Hidden system
families are left out and the default family is always in. ``PenFontRegistry/faces(of:cache:)``
lists a family's faces — a static font's weight class, every hundred a variable font's
weight axis spans — for a weight menu. Both are cached until
``PenFontRegistry/generation`` moves.

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
``EditableDocument/bindableVariables(ofType:at:)`` asks by type instead, for a picker that
binds inside a structured value — a fill's color, a gradient stop — where no property path
names the type.

### Mentions

A comment's or a note's reply box finds `@mentions` in its raw text with
``PenMention/mentions(in:)``, and the name being typed at the caret with
``PenMention/query(atCaret:in:)`` — both by the rule note markdown parses with
(<doc:NoteMarkdown>), so the pills drawn while typing agree with the note drawn after.

## Topics

### Queries

- ``EditableDocument/resolve(expandedID:)``
- ``EditableDocument/inspect(expandedID:)``
- ``EditableDocument/inspect(_:)``
- ``EditableDocument/bindableVariables(for:at:)``
- ``EditableDocument/bindableVariables(ofType:at:)``
- ``PenSchema/fields(for:)``
- ``PenSchema/field(_:for:)``
- ``PenFontRegistry/availableFamilies(cache:)``
- ``PenFontRegistry/faces(of:cache:)``
- ``PenMention/mentions(in:)``
- ``PenMention/query(atCaret:in:)``

### Results

- ``NodeInspection``
- ``BindableVariable``
- ``PenPropertyDefault``
- ``PenMention``
