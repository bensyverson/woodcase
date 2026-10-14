# What a slot's list means: suggested components, not accepted types

**2026-10-14, leaf J41Aua.** Finding: the premise of J41Aua ("slots refuse nodes of a type they don't accept") does not hold in the Pen format. A frame's `slot` list names **suggested reusable components**, by id. It does not restrict what a slot holds. Woodcase had documented it as "accepted node types", and so had Penumbra's interaction spec §4.3.4 ("Slots accept only what their slot type allows"). Both were wrong.

## Evidence

- **The schema.** `local/Pen-Schema-2.20.md` (and 2.17): `slot?: false | string[]` — "Marks frame as a slot for component instances. Array entries are IDs of recommended reusable child components (e.g. menu items inside a menu bar)." `local/Pen-Format.md` § Slots: the list holds `"round-button"` and `"icon-button"`, and "Pencil … lets users insert instances of the suggested components … with a single click."
- **Pen's editor code** (read-only from `/Applications/Pen.app/Contents/Resources/app.asar`, `grep -a` for `isSlotInstance` and `.slot`):
  - The Slot inspector section resolves each entry with `documentManager.getNodeByPath(entry)`, keeps the ones that are `reusable`, and offers them for insertion. Its "add" action pushes `component.id` onto the list.
  - On paste and import, slot entries are remapped like node ids, next to `ref` targets and `descendants` keys.
  - `canAcceptChildren` never reads the list. Inside an instance, a frame takes children only if it is a slot (`isSlotInstance`) and is still empty, or its children are already overridden. Any node type passes.
- **Real files.** `python3 -I scripts/slot-survey.py . local` walks every `.pen` file under those roots. Every list in a Pen-authored library (`kit.lib.pen`, `shadcn.lib.pen`) is component ids, such as `["ugPph", "UG4ed"]`, or empty. Type names such as `["text", "frame", "ref"]` appear only in fixtures Woodcase wrote by hand (`tree-slot.pen`, `slot-fill.pen`) and in the `woodcase help design` recipe, which taught agents to write them.

## Consequence

A refusal keyed on node type would refuse *every* insert into every real slot, because no node's type is a component id. So J41Aua built no type check. What changed instead:

- `ComponentSlotInfo.acceptedTypes` is renamed `suggestedComponentIDs`. The `FrameData.slot` doc comment and the `help design` recipe (now `"slot": []`) are corrected, and EditingDocuments.md says a slot suggests and does not restrict.
- Nested inserts raise no question, because there is no rule to apply to descendants.

## Open questions for Ben

1. **Does Penumbra want a rule Pen does not have?** For example, "only the suggested components may fill a slot that names some." That would be a Woodcase ruling stricter than Pen. Pen would then still accept files Woodcase refuses to write.
2. **Pen's real rule** is the one Penumbra's reparent and creation drags need for a prohibition cursor: inside an instance, only a slot frame accepts children, and only while it is empty or already overridden. In Woodcase, filling an instance's slot is an override of that slot's `children`, not a `MoveNode`. A "can this drop target take children?" query would encode that rule. It is not built yet.
3. Woodcase decodes `slot` as `[String]?`. The schema also allows `slot: false`, which Pen never writes but a hand-written file could. That case is untested.
