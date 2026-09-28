# Which node a `descendants` key names: Pen's rule, measured (2026-09-26)

Author: Claude (Opus), leaf `ILYyZi`. Found by `koyac9` (readctx): `banking.pen`'s theme
instances `#YGJ0d` / `#8ruxp` carry overrides keyed `2592p`, `G6llC`, `T2IOh`, `WKey6` —
icons that `nSNTs`' own transaction rows write into their `URnQO` slot. Pen applies those
bare keys; Woodcase applied only `ALu8G/2592p`, and lint called the eight bare keys
`override-target-not-found`.

## The rule

Pen reads a key one `/`-separated step at a time, and which node a step may name depends
on **who wrote the node** — the component the instance places, or a component nested in
it.

1. **The first step names any node the component itself wrote, however deep.** That is
   its own tree, *and* the slot content it writes for a nested instance — a `children`
   entry in that instance's `descendants`, or `children` written on the nested `ref`
   node itself — and the slot content inside that, at any depth. A node another
   component wrote (a nested component's own tree, or slot content *that* component
   writes) is never a first step.
2. **Each later step names a node placed below the previous one** that was written by a
   component the key has already entered — or, when the previous step is an instance, a
   node of that instance's component's own tree, which enters that component.
3. **Canonical form.** Pen re-saves every key it resolves in one form: the bare id for a
   node the component wrote, and the instance-id path for any other
   (`Mid01/Ins2A/Inj2`). Every key it cannot resolve is logged as
   `[ERROR] Invalid override path '<key>' for '<component>'` and dropped from the file.
4. **Two keys, one node.** Only one override applies: the key written **last** in the
   file, **whole** — a bare `{"height": 10}` and a later path `{"fill": green}` on the
   same node draw green at the *original* height; swapping their order draws the bare
   one. Pen's re-save keeps the winner under the canonical key.
5. **Content an instance writes into a slot itself** is not addressable by that
   instance's own keys: `{"Ins0A/Hole1": {"children": [NewY]}, "Ins0A/NewY": …}` and the
   bare `NewY` are both invalid. Nor can a nested instance's keys reach content its
   *enclosing* component wrote into it (`Ins0A`'s own key `Inj01`, for content `Scr01`
   wrote into `Ins0A`, is invalid for `Slot1`).
6. **Duplicate ids** are not a rule question: Pen logs `Document had duplicate IDs` and
   renames every repeat on load (first in document order keeps the id), document-wide —
   a node injected in a slot collides with any other node of that id, in any component.
   So a bare key names the first; a path to a renamed repeat is invalid.

## Measurements

`pen` CLI 0.3.9 headless, sandbox off. The committed fixture reproduces every row except
the scratch-only ones (marked †):

```
scripts/pen-oracle Tests/WoodcaseTests/Fixtures/slot-override-keys.pen --scale 1 --accept-invalid --no-layout
```

`Scr01` places `Ins0A` (a `Slot1` instance) and writes into its `Hole1` slot: `Inj1`, a
frame `InjF` holding `Deep`, and `InsB` (a `Slot2` instance) whose `Hole2` slot it fills
with `Inj3`. `Slot1` itself has `Pln01`. `Scr03` places `Mid01`, an instance of `Scr02`,
which writes `Inj2` into its own `Ins2A`'s slot. Injected nodes are red; blue = bare key
applied, green = path applied. Verdicts are read from the export (pixel probes with
`scripts/probe-pixels.swift`) and cross-checked against the re-save.

| Artboard | Key(s) on the instance | Pen draws | Pen re-saves |
|---|---|---|---|
| bare-injected | `Inj1` | blue | `Inj1` |
| path-injected | `Ins0A/Inj1` | green | `Inj1` |
| bare-and-path | `Inj1` blue, then `Ins0A/Inj1` green | green | `Inj1` green |
| (scratch †) | `Ins0A/Inj1` green, then `Inj1` blue | blue | — |
| bare-and-path-no-merge | `Inj1` height 10, then `Ins0A/Inj1` green | green, height 20 | `Inj1` green |
| bare-nested-plain | `Pln01` | nothing | dropped |
| bare-injected-deep | `Deep` (child of injected frame) | blue | `Deep` |
| bare-injected-ref | `InsB` (injected instance) | blue | `InsB` |
| bare-injected-twice | `Inj3` (slot in a slot) | blue | `Inj3` |
| bare-injected-replace | `Deep` → `{"type": "ellipse", …}` | blue ellipse | `Deep` |
| path-injected-twice | `Ins0A/InsB/Inj3` | green | `Inj3` |
| path-skips-injected-ref | `Ins0A/Inj3` | green | `Inj3` |
| path-from-injected-ref | `InsB/Inj3` | green | `Inj3` |
| path-injected-deep | `Ins0A/Deep` | green | `Deep` |
| path-through-injected-frame | `InjF/Deep` | green | `Deep` |
| path-ref-injected-frame | `Ins0A/InjF/Deep` | green | `Deep` |
| path-ref-then-slot | `Ins0A/Hole1/Inj1` | green | `Inj1` |
| path-slot-first | `Hole1/Inj1` | nothing | dropped |
| path-plain-frame | `PF1/PX1` (no slot at all) | green | `PX1` |
| outer-bare | `Inj2` on a `Scr03` instance | nothing | dropped |
| outer-short-path | `Mid01/Inj2` | nothing | dropped |
| outer-full-path | `Mid01/Ins2A/Inj2` | green | `Mid01/Ins2A/Inj2` |
| bare-ref-children | `RtC`, written as `children` on the nested ref | blue | `RtC` |
| (scratch †) | instance fills `Ins0A/Hole1` with `NewY`, keys `Ins0A/NewY` / `NewY` | nothing | dropped |
| (scratch †) | `Ins0A`'s own key `Inj01` naming content `Scr01` wrote | nothing | dropped |
| (scratch †) | two injected `Dup01` in one component; `Dup01` / `InsA2/Dup01` | first blue / nothing | second renamed |

† Scratch probes under the session scratchpad (`ILYyZi-probe/`), not committed: the
order-reversed pair cannot be pinned by Woodcase (below), and the rest are rows 5–6.

Side finding: Pen's own `Get` visitor throws (`TypeError: cannot read property of
undefined`) on a document holding a `ref` that writes `children` of its own, though it
exports and saves it fine — hence `pen-oracle --no-layout`, added for this fixture.

## What Woodcase does now

- `PenOverrideKeyResolver` implements rules 1–3: it places a component's expansion (ids,
  paths, and which scope wrote each node, without building the expansion) and answers
  each key with its canonical key and site — the component's tree, slot content it
  wrote, or a nested component's node.
- `PenRefExpander` files an instance's overrides through it
  (`PenRefExpander.OverridePlan`): tree nodes are patched before expansion as before,
  slot content is patched *inside the fill that writes it* before the nested instance
  expands (`PenNodePatcher.applySlotContentOverrides`), and the rest by path after
  expansion. A key the resolver cannot place keeps its old treatment.

  > **Superseded 2026-09-26 (leaf `MFvCPv`):** "the rest" is now handed to the nested
  > instance its path starts at, before it expands, and an unplaced key is dropped except
  > as the follow-up below says.
- **Rule 4, deliberately different:** Woodcase's `descendants` is a dictionary, so the
  order keys were written in is lost (changing that is a Models Codable change). The key
  that **sorts** last wins, whole. Woodcase writes `.pen` with sorted keys, so this is
  Pen's answer for any file Woodcase saved; for a hand- or Pen-written file whose
  colliding keys are written out of sorted order, the two differ.
- The override guard (`validateOverrideTarget`, which `lint`'s `override-target-not-found`
  reuses) accepts a key the resolver places, so lint and the expansion agree.
  `banking.pen` now lints with no `override-target-not-found`.

## Left open

- Rule 5 is not in the guard: the guard's key list still offers `Ins0A/NewY` for content
  an instance wrote itself, which Pen drops (Woodcase's expansion also draws nothing for
  it, so only lint disagrees).

  > **Closed 2026-09-26 (leaf `MFvCPv`), and the parenthesis was wrong.** Woodcase's
  > expansion *did* draw such an override when the slot was the instance's own component's
  > (`slot-fill.pen`: `Inst0` fills `Body` with `Note0`, key `Note0`) — the patcher walked
  > into the fill it had just written — and `woodcase override Inst0/Note0` was a
  > documented feature. Pen drops it (follow-up below). The patcher no longer enters
  > children an override wrote; the guard refuses such a key with
  > `EditingError.overrideOnOwnSlotContent`, naming the slot to rewrite; lint reports it.

- A path naming a nested *instance* by its structural key (`Ins0A/Ins0B`) is accepted by
  lint but not applied by the expander, whose expanded instance root carries the
  component's id (`…/Ins0B/Slot2`). A bare key naming an instance the component wrote
  into a slot (`InsB`) does apply now, because slot content is patched before it expands.

  > **Closed 2026-09-26 (leaf `MFvCPv`).** Pen applies such a key (follow-up). A key
  > naming a node another component wrote is now handed to the nested instance its path
  > starts at (`PenRefExpander.handDown`) and applies as one of that instance's own keys,
  > before its nested refs expand — so `Mid/Dot` patches `Dot`'s `ref` node, and a slot
  > fill written that way is expanded and prefixed like any other.

- Duplicate ids (rule 6) are resolved to the first in tree order, not renamed.
- A debug build overflows a 512 KiB task stack expanding four nested instances
  (`woodcase tree` on `Top → Scr03 → Mid01 → Scr01 → Ins0A → InsB` exits 138, "Thread
  stack size exceeded"; `EditableDocument.expanded` runs on the cooperative pool). This
  leaf moved `expandRef`'s pre-recursion work into helpers to keep its own frame small
  (the new code had pushed the fixture over), and kept the fixture's `Scr03` chain one
  instance shallower; the underlying frame size is not fixed.

  > **Fixed in the expander 2026-09-26 (leaf `PJwhm2`)** — see
  > [debug-stack-depth](2026-09-26-debug-stack-depth.md). Parsing, variable resolution and
  > layout still recurse; that finding says how deep each reaches.

## Follow-up: the two keys lint accepted (2026-09-26, leaf `MFvCPv`)

`pen` CLI, headless, sandbox off, on a scratch probe
(`scripts/pen-oracle <probe>.pen --scale 1 --accept-invalid --no-layout`); verdicts from
the exports and the re-save. `SlotA` has an empty `HoleA`; `SlotB` places `InsBB`, an
instance of the red `SlotC`; `CmpD` places `InsD1`, an instance of `SlotB`.

| Instance of | Key(s) | Pen draws | Pen re-saves |
|---|---|---|---|
| `SlotA` | `HoleA` fill `[NewY1]` red, then `NewY1` blue | red | fill only; `NewY1` dropped |
| `SlotA` | `HoleA` fill `[NewY2]` red, then `HoleA/NewY2` green | red | fill only; path dropped |
| `CmpD` | `InsD1/InsBB` green | green | `InsD1/InsBB` |
| `CmpD` | `InsD1/InsBB` width 60 | red, 60 wide | `InsD1/InsBB` |
| `SlotB` | `InsBB` blue (control) | blue | `InsBB` |

So rule 5 holds for an instance's fill of its *own* component's slot, not only a nested
one, and a path may name a nested component's instance, whose root it patches. The
expander, the guard and lint now agree with every row: `PenRefExpanderPenKeyTests`,
`OwnSlotContentGuardTests`, and `InjectedAddressTests` / `InjectedAddressCommandTests`,
whose override tests were rewritten from "applies" to "refused".

A key the resolver cannot place is now dropped, as Pen drops it, with two exceptions it
cannot judge: a bare id still patches the component's tree by id, and a path through a
nested `ref` the instance itself repoints (`Tab01` with `ref=CurC`, then `Tab01/Lbl02`)
is handed down to that ref — the resolver reads the ref as authored. Before, an
unplaced path was applied after expansion by the id it spelled. Neither old nor broader
readings survive: handing every unplaced path down applied `outer-short-path`, which Pen
drops, and the old by-id reading would now reach an instance's own fill of a nested slot
(`Inn/NewY` in `PenRefExpanderPenKeyTests`), whose ids are now prefixed like any other.

> **Updated 2026-09-26 (leaf `W0YLOb`):** Ben ruled that an override *addressed* to
> content an instance wrote into its own slot is rewritten into that slot fill instead of
> refused. `EditableDocument.slotFillRewrite(of:)` finds the fill through the same walk
> that decides what is own content (`ownSlotContentKeys`, not `PenOverrideKeyResolver`,
> which by design leaves an instance's own fill out) and turns the write into one
> override of the slot's key carrying the whole `children` list, with the node changed —
> or, for a node inside an injected `ref`, that ref's own `descendants` changed inside the
> fill. `BatchApplier` plans every `override` line through it, so the verb, `apply` and
> `doc.override` agree; the line reports a `slotFillRewrite` note naming the slot, and the
> activity log records (and undo reverses) the slot override. Woodcase never writes a key
> Pen drops. `EditingError.overrideOnOwnSlotContent` stays, but only a raw
> `EditOperation.OverrideDescendant` naming such a key can raise it now; lint still reports
> such keys in hand- or Pen-written files, with the rewriting `override` as the remedy.
> Left open: nothing removes a stale key of that kind short of Pen's own re-save — a
> removal op would need an undo that re-adds a key the guard refuses.
