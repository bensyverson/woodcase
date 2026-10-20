# 2026-10-20 — Natural paths for the properties Woodcase stores in metadata

**Ruling (Ben, 2026-10-20, Penumbra session 39): an agent, the CLI, the scripting API and the inspector set a Woodcase-owned property by a natural path, and Woodcase decides where it is stored.** Today they name the storage: `woodcase set design.pen Card common.metadata.woodcase.strokeDash=[4,2]`. After this plan they write `kind.strokeDash=[4,2]`, and the value still lands in `metadata.woodcase`, where Pen keeps it.

## Why

- **Agents guess natural names.** An agent that knows Pen's format, Figma or CSS reaches for `blendMode` or `strokeDash`, not `common.metadata.woodcase.strokeMiterLimit`. Every wrong guess costs a turn, or a value written somewhere nothing reads.
- **Storage is a decision we may change.** These keys live in metadata only because Pen's format lacks them, and Pen keeps metadata (DocC `PenMetadataNamespace.md`). If Pen adds a native dash, Woodcase moves the storage, and no agent's or inspector's path breaks.
- **Pen-style edits keep working.** Penumbra hosts Pen's MCP, where an agent writes `Update("id", {blendMode: "multiply"})` in Pen's own style. A natural key there should land in the right place.
- **It settles node blend mode.** Pen drops a top-level node `blendMode` on load, so it moves into metadata (TesTbK; Penumbra `project/2026-10-14-feature-enhancements-plan.md` §5 item 10). Its path, `kind.blendMode`, stays as it is: it is this rule's first case.

## The rule

A key is **Woodcase-owned** when it stands in for a property Pen's format lacks: the rows `PenSchema.woodcaseFields(for:)` lists today, plus the node blend mode.

| Natural path | Stored at | Node types |
|---|---|---|
| `kind.blendMode` | `metadata.woodcase.blendMode` (TesTbK) | every type that takes one today |
| `kind.strokeDash` | `metadata.woodcase.strokeDash` | frame, rectangle, ellipse, polygon, path, line |
| `kind.strokeDashOffset` | `metadata.woodcase.strokeDashOffset` | as above |
| `kind.strokeMiterLimit` | `metadata.woodcase.strokeMiterLimit` | as above, but not line |
| `spread` on a shadow in `kind.effect` | `metadata.woodcase.shadowSpread`, one entry per spread shadow, by its place among the effects | every type that takes effects |
| `common.locked` | `metadata.woodcase.locked` | every type |
| `kind.defaultTextStyle` | `metadata.woodcase.defaultTextStyle` | text |
| `kind.spans` | `metadata.woodcase.spans` | text |

`common.locked` sits under `common` because every type takes it. The rest sit under `kind`, beside their Pen siblings (`kind.strokeWidth`, then `kind.strokeDash`). Shadow spread has no path of its own because paths don't address array elements: a `spread` field on a shadow object, which is where CSS, Figma and Sketch put it, is the natural spelling.

1. **Every reader and writer uses the natural path.** That covers `woodcase set` and `get`, batches, `tree --props`, `woodcase schema` and `woodcase help`, the `doc` API in `woodcase js`, `PenSchema.field(_:for:)` and the inspector's rows. `get` and `tree` print the natural path, and only the raw `.pen` JSON shows the metadata.
2. **One mapping, in one place.** Each Woodcase-owned `PenMetadata.WoodcaseKey` names its natural path beside its storage path. The codec converts between them, so no consumer spells a storage path.
3. **Writing a raw storage path is refused, with an error that teaches.** For example: `common.metadata.woodcase.strokeDash is stored for you; write kind.strokeDash`. One way in, so two spellings can't drift apart. Reading the raw metadata (`common.metadata`) still shows what's stored.
4. **Woodcase concepts with no Pen counterpart get a namespace of their own.** See *Widened the same day* below.

> **Widened the same day (Ben, 2026-10-20):** this rule first left the code-generation keys, the note keys and rich-text `spans` at their raw `common.metadata.woodcase.*` paths, as "Woodcase's own vocabulary". That was wrong for `spans`: Pen's format has had no rich text since 2.17 (DocC `PenRichText.md`), so spans stand in for a missing property. They are now in the table above as `kind.spans`, beside `kind.content`. And "own vocabulary" only meant there was no Pen name to match, not that agents should type a storage path. So the rule is now that **every key Woodcase stores in metadata has a natural path**:
>
> - **Code generation:** `codegen.props`, `codegen.role`, `codegen.states`, `codegen.action`, `codegen.scroll`. Only Woodcase reads these, so rule 3 applies: writing the raw path is refused with a pointer to the natural one. The namespace keeps them clear of any future Pen field.
> - **Notes:** `note.*` for the note keys and a note's text style, as **aliases only**. Other tools read notes by their raw keys: the note convention (DocC `PenPostItConvention.md`) is meant to be legible without Woodcase, for example to an agent working in Pen through Pen's MCP. So the raw keys stay the published format, and writing them is still accepted. Both spellings write the same storage key, so they can't drift. Woodcase's own tools print the `note.*` spelling. This is its own leaf so it can be dropped without touching the rest (Ben was open on it; integrator's recommendation).
> - **Unchanged:** a text's protected `textDecoration`. Underline and strikethrough are native Pen properties (`kind.underline`, `kind.strikethrough`); Woodcase only mirrors them in metadata because Pen strips the native keys, and it keeps the two in step on every write. The natural path already exists.
5. **The typed accessors don't change** (`PenNode.strokeDash`, `.strokeMiterLimit`, `.isLocked`, `shadowSpread(forEffect:)`). Renderers, emitters, lints and the planner already read through them.
6. **An instance override of a metadata-backed property is stored in the override's own `metadata.woodcase`, and Woodcase merges it per key** (Ben, 2026-10-20, Penumbra session 40). Overriding `kind.strokeDash` on a descendant writes `descendants[<id>].metadata.woodcase.strokeDash`. On expansion, an override's `metadata.woodcase` merges key by key over the component node's, rather than replacing its whole `metadata` the way the top-level JSON merge replaces any other key; so the component's other metadata keys (its notes, its other Woodcase keys) still reach the instance, and later edits to them still flow through. At the instance root, the `ref` node's own `metadata.woodcase` merges key by key over the component root's (`transferCommonProperties` carries no metadata today). Before this, TesTbK stored such overrides as raw keys (`blendMode` in `descendants`), which Pen drops. In Pen's view an override's `metadata` shadows the component child's whole metadata, but Pen draws none of it, so nothing it shows changes. Premise to check first with the `pen` CLI: that Pen keeps `metadata` inside a `descendants` override and on a `ref` node through load and save; if it doesn't, stop and report.

   > Corrected 2026-10-20 (same session): **the premise failed, and Ben kept the rule.** With `pen` CLI 0.3.11 (leaf 9Sw8C0, w-paths), Pen drops `metadata` inside a `descendants` override and on a `ref` node on save, even when set through Pen's own `Update`; it also drops TesTbK's raw override keys ("Unknown override property: blendMode"). It keeps metadata only on ordinary nodes and components. So no spelling of an instance override of a Woodcase-owned property survives Pen, and an instance's lock (`common.locked` on a ref) never did. Ben: build the rule anyway — transfers are expected one way, Pen → Penumbra, not round trips, and Pen ignores our metadata regardless; no lint for the loss. The sentence above saying Pen draws none of it so nothing it shows changes still holds; what Pen loses is the override itself. A holder node Pen would keep is parked in `project/backlog.md` (2026-10-20).

## Tasks

TesTbK (node blend mode into metadata, `kind.blendMode` kept) lands first, after kTi6la. The mapping touches the same `WoodcaseKey` files every metadata-key leaf does, so these run alone among metadata-key work (gotchas, 2026-10-15). The Penumbra inspector's switch to the natural paths is a Penumbra leaf, filed beside this import.

```yaml
tasks:
  - title: "Natural paths for the properties Woodcase stores in metadata"
    ref: natural
    labels: [penumbra-editor, agent-ergonomics]
    desc: |
      Ben's ruling, 2026-10-20 (Penumbra session 39): agents, the CLI, the scripting API and the inspector set a Woodcase-owned property by a natural path (kind.strokeDash, common.locked, a shadow's spread), and Woodcase decides where it is stored. Design, table and rules: project/2026-10-20-natural-paths-for-woodcase-properties.md. Read it before claiming either leaf.
    children:
      - title: "Woodcase-owned properties read and write through natural paths"
        ref: paths
        blockedBy: [TesTbK]
        desc: |
          Build the mapping and its readers and writers, following the design doc's table and rules 1-3 and 5: kind.strokeDash, kind.strokeDashOffset, kind.strokeMiterLimit, common.locked and kind.defaultTextStyle (kind.blendMode is already natural after TesTbK; fold it into the same mapping). Each Woodcase-owned PenMetadata.WoodcaseKey names its natural path. The codec converts paths both ways, and no consumer spells a storage path. A write to a raw storage path is refused with an error that names the natural path (see project/agents/cli-design.md: errors that teach). PenSchema.woodcaseFields(for:) and woodcase schema list the natural paths. Update WoodcaseEditor.md, PenMetadataNamespace.md, woodcase help and the `doc` TypeScript declaration. Breaking change (stage BUILD): build Penumbra and RapidPro after the squash, and tell the integrator which Penumbra inspector paths change.
        criteria:
          - "woodcase set design.pen Card kind.strokeDash=[4,2] stores the dash under metadata.woodcase and every renderer draws it unchanged"
          - "woodcase get and tree --props print kind.strokeDash, common.locked and the other natural paths, never their storage paths"
          - "A write to common.metadata.woodcase.strokeDash is refused with an error naming kind.strokeDash"
          - "woodcase schema lists each Woodcase-owned property at its natural path, and the doc API in woodcase js reads and writes the same paths"
          - "One table maps each Woodcase-owned key to its natural path, and a test fails when a new woodcaseFields row has no natural path"
      - title: "A shadow's spread is a field of the shadow"
        ref: spread
        blockedBy: [paths]
        desc: |
          Paths don't address array elements, so a shadow's spread is spelled as a `spread` field on the shadow object in kind.effect, as CSS, Figma and Sketch put it. Writing kind.effect with a spread on a shadow stores it in metadata.woodcase.shadowSpread (one entry per spread shadow, by its place among the effects, as today). Reading kind.effect puts the spread back on its shadow. The shadow-spread-stale lint and PenShadowSpread keep working, and reordering or removing effects keeps each spread on its own shadow. Design doc: project/2026-10-20-natural-paths-for-woodcase-properties.md.
        criteria:
          - "Writing kind.effect with a shadow carrying spread 4 stores it in metadata.woodcase.shadowSpread, and the CG renderer draws the spread"
          - "Reading kind.effect returns each shadow with its own spread"
          - "Reordering and removing effects in one write keeps each spread on its own shadow, and a spread whose shadow is gone is dropped"
```
