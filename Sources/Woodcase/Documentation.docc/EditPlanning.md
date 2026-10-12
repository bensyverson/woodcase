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
let plan = try EditPlanner.plan(.set(["kind.fills": "#E5484D"]), at: address, in: document)
plan.storage      // .instanceOverride — Label is inside the instance Chip
plan.operations   // [.overrideDescendant(Chi01, Lbl01, ["fill": "#E5484D"])]
try session.submit(.local(LocalEdit(operations: plan.operations)))
```

An editor that already holds a ``ResolvedNodeAddress`` passes it instead of a
``NodeAddress``; the plan is the same.

### Intents

| Intent | Plans as |
|---|---|
| ``EditIntent/set(_:)`` | `setProperties` on a node with storage of its own; an override on the instance for a node inside one |
| ``EditIntent/override(_:unset:)`` | a `descendants` entry, or the instance's root overrides when aimed at the instance itself |
| ``EditIntent/resetOverride(_:)`` | an override that only unsets keys |
| ``EditIntent/bind(property:variable:)`` | a set of `$name`, refused unless the variable exists with the right type |
| ``EditIntent/unbind(property:)`` | a set of the value the bound variable has under the node's theme |

**Edits inside an instance are overrides.** A set aimed inside an instance is planned
exactly as the override it has to be — property paths translated to the raw keys the
`descendants` map uses, published parameters routed, content the instance wrote into its
own slot written into that slot's fill — and carries a
``WriteDivergence/Kind/storedAsOverride`` note. Aimed at an instance root, a set writes
the `ref` node's own properties (`common.x`, `common.enabled`); the component root's
properties as the instance shows them are an override.

### What is refused

| Code | When |
|---|---|
| ``EditRefusal/Code/outOfRange``, ``EditRefusal/Code/offStep`` | a number outside the property's ``PenValueConstraint`` — an opacity of 7, a negative width, a fractional polygon count, a `lineHeight` written in points |
| ``EditRefusal/Code/undefinedVariable`` | a `$name` the document (and the libraries read with it) does not define; text content alone keeps an undefined `$word` as literal text |
| ``EditRefusal/Code/variableTypeMismatch`` | a `$name` of a type the property does not take — a color bound to an opacity |
| ``EditRefusal/Code/positionIgnoredByLayout`` | an `x` or `y` on a node its parent's layout places; ``EditRefusal/suggestion`` is the `layoutPosition` write that would honor it |
| ``EditRefusal/Code/unknownProperty``, ``EditRefusal/Code/invalidForm`` | a key the node's type lacks, a value of a form it does not take |

Each refusal carries ``EditRefusal/property`` and ``EditRefusal/expected`` — the range
or form that would have been accepted — so an inspector can show it beside the field.
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

## Topics

### Planning

- ``EditPlanner``
- ``EditIntent``
- ``EditPlan``

### Refusals

- ``EditRefusal``
- ``PenValueConstraint``
