# What a slot's list means: suggested components, not accepted types

**2026-10-14, leaf J41Aua.** Finding: the premise of J41Aua ("slots refuse nodes of a type they don't accept") does not hold in the Pen format. A frame's `slot` list names **suggested reusable components**, by id. It does not restrict what a slot holds. Woodcase had documented it as "accepted node types", and so had Penumbra's interaction spec §4.3.4 ("Slots accept only what their slot type allows"). Both were wrong.

> **Correction (2026-10-23, leaf zeSAV7):** this doc's evidence section cited Pen's editor code, read from Pen.app's `app.asar`. Ben had ruled on 2026-10-14 that we never read Pen.app's bundled code, or appear to, so that evidence was wrong to use. The finding itself holds: the published schema and the `pen` CLI both show that the `slot` list is a suggestion and restricts nothing. The three claims about the editor's internals are struck, because they cannot be re-verified through the CLI (see Evidence), and open question 2 no longer states a Pen rule.

## Evidence

- **The schema.** `local/Pen-Schema-2.20.md` (and 2.17): `slot?: false | string[]` — "Marks frame as a slot for component instances. Array entries are IDs of recommended reusable child components (e.g. menu items inside a menu bar)." `local/Pen-Format.md` § Slots: the list holds `"round-button"` and `"icon-button"`, and "Pencil … lets users insert instances of the suggested components … with a single click."
- **The `pen` CLI** (2026-10-23, CLI 0.3.11; fixture `project/fixtures/slot-semantics-probe.pen`). An instance of a component with three frames, one with `"slot": ["btnComp"]` (a component id), one with `"slot": ["text"]` (a type name) and one with no `slot`, took `Insert` calls for a text into the first, a rectangle into the second and a text into the third, with no error or warning. A rectangle in a slot that names only `"text"` is accepted, so the list does not restrict by type. Pen saved each as `descendants.<frameId>.children`, an override of the frame's `children`, which is how Woodcase models filling a slot.
- **Not verified (removed).** The three claims below rested on reading Pen's bundled editor code, which Ben ruled out (2026-10-14; Penumbra `AGENTS.md`). The CLI cannot show them and nothing published states them, so none stands:
  - how the editor's Slot inspector section resolves, filters and extends the list;
  - that paste and import remap slot entries like node ids (an `execute` `Copy` of a frame holding reusable components makes instances of them, so it does not exercise a remap);
  - the editor's own drop rule, "inside an instance a frame takes children only if it is an empty slot". The CLI's `Insert` did *not* enforce it: it filled the plain frame (third call above). That is the scripting path; whether the canvas's drag-and-drop is stricter is unknown.
- **Real files.** `python3 -I scripts/slot-survey.py . local` walks every `.pen` file under those roots. Every list in a Pen-authored library (`kit.lib.pen`, `shadcn.lib.pen`) is component ids, such as `["ugPph", "UG4ed"]`, or empty. Type names such as `["text", "frame", "ref"]` appear only in fixtures Woodcase wrote by hand (`tree-slot.pen`, `slot-fill.pen`) and in the `woodcase help design` recipe, which taught agents to write them.

## Consequence

A refusal keyed on node type would refuse *every* insert into every real slot, because no node's type is a component id. So J41Aua built no type check. What changed instead:

- `ComponentSlotInfo.acceptedTypes` is renamed `suggestedComponentIDs`. The `FrameData.slot` doc comment and the `help design` recipe (now `"slot": []`) are corrected, and EditingDocuments.md says a slot suggests and does not restrict.
- Nested inserts raise no question, because there is no rule to apply to descendants.

## Open questions for Ben

1. **Does Penumbra want a rule Pen does not have?** For example, "only the suggested components may fill a slot that names some." That would be a Woodcase ruling stricter than Pen. Pen would then still accept files Woodcase refuses to write.
2. **Pen's drop rule is unknown.** Penumbra's reparent and creation drags need a prohibition cursor, so they need a rule for what an instance's frames accept. This doc once stated Pen's rule (only an empty or overridden slot accepts children), but that came from Pen's code and is struck (see the correction above); the CLI's `Insert` accepts children into a non-slot frame of an instance. So the rule is Ben's to set, not Pen's to copy. *Answered 2026-10-23: Ben's ruling in Penumbra's spec §13.5 (Slots) is that an instance's slot frame, at any depth, takes children and nothing else inside an instance does (Woodcase leaf OAxopm).* In Woodcase, filling an instance's slot is an override of that slot's `children`, not a `MoveNode`. A "can this drop target take children?" query would encode whatever rule is chosen. It is not built yet.
3. Woodcase decodes `slot` as `[String]?`. The schema also allows `slot: false`, which Pen never writes but a hand-written file could. That case is untested.
