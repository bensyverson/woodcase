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

### What is refused

| Code | When |
|---|---|
| ``EditRefusal/Code/outOfRange``, ``EditRefusal/Code/offStep`` | a number outside the property's ``PenValueConstraint`` — an opacity of 7, a negative width, a fractional polygon count, a `lineHeight` written in points — or outside a nested key's ``PenNestedShape/Field/constraint``: a gradient stop at position 2, a fill's opacity of 1.5, a negative blur radius |
| ``EditRefusal/Code/undefinedVariable`` | a `$name` the document (and the libraries read with it) does not define; text content alone keeps an undefined `$word` as literal text |
| ``EditRefusal/Code/variableTypeMismatch`` | a `$name` of a type the property does not take — a color bound to an opacity — or, inside a structured value, of a type its nested key does not take: a number variable as a fill's color |
| ``EditRefusal/Code/setInsideInstance`` | a set, bind or unbind aimed inside a component instance; ``EditRefusal/suggestion`` is the override to request instead |
| ``EditRefusal/Code/positionIgnoredByLayout`` | an `x` or `y` on a node its parent's layout places; ``EditRefusal/suggestion`` is the `layoutPosition` write that would honor it |
| ``EditRefusal/Code/unknownProperty``, ``EditRefusal/Code/invalidForm`` | a key the node's type lacks, a value of a form it does not take |

Each refusal carries ``EditRefusal/property`` and ``EditRefusal/expected`` — the range
or form that would have been accepted — so an inspector can show it beside the field. For
a value inside a structured one, ``EditRefusal/property`` is still the key written
(`kind.fills`) and the message names the spot (`kind.fills[0].colors[1].position`). The
same spot rides in ``EditRefusal/nested``, a typed ``EditRefusal/NestedLocation`` — here
`[.index(0), .key("colors"), .index(1), .key("position")]`, with
``EditRefusal/NestedLocation/layerIndex`` 0 and ``EditRefusal/NestedLocation/key``
`"position"` — so an inspector places the refusal under the right layer without reading
the sentence; it is `nil` for a refusal about the property itself. Only
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

### Previewing

- ``EditableDocument/previewNodes(for:)``
- ``EditableDocument/PreviewError``
- ``EditableDocument/materializeSnapshot(overlaying:isolation:)``

### Refusals

- ``EditRefusal``
- ``PenValueConstraint``

### Inspecting

- <doc:InspectingNodes>
