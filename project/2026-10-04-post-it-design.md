# 2026-10-04 — Sized notes, the post-it convention and the Post-it look: design and plan

**Task:** `SuCn6G` in [2026-10-04-penumbra-editor-support.md](2026-10-04-penumbra-editor-support.md); RapidPro's `uVJjI9` "Draw post-its at parity with Woodcase" follows it ([../../RapidPro/project/2026-10-04-post-it-parity.md](../../RapidPro/project/2026-10-04-post-it-parity.md)).\
**Source:** read-only research by a subagent of Penumbra's main thread; decisions by the main thread under Ben's delegation.\
**Ben's ruling R10:** Woodcase owns the post-it convention and the default Post-it look; RapidPro matches pixel for pixel. A flat square with a soft shadow and slight rounding; 200×200 Post-it yellow by default, tintable to any color; the author's name in lighter text bottom-left; author = creator, or whoever edited it after copying; font and size editable; resolved notes visibly resolved.

## Decisions (main thread, 2026-10-04)

1. **Every `note` gets the look**, whatever its `metadata.type` (without the convention it has no author line). `prompt` and `context` gain sizes but stay undrawn — Pen gives `context` a prompting meaning.
2. **Tint lives in `metadata.tint`** (`#RRGGBB`, absent = Post-it yellow; presets written as hex; Woodcase owns the preset palette). Pen's schema gives notes no fill and Pen strips undeclared keys, so a note `fill` likely wouldn't survive. Re-decide only if leaf W0 shows Pen keeps a note `fill` and Ben wants variable-bound tints.
3. **The look is produced as an expansion** — a synthesized node subtree both renderers draw with code they already MAE-gate — so parity is structural, unlike the browser placeholder whose label math RapidPro re-implements.
4. **The look's numbers are a visual call for Ben.** `Style.standard` below is v1; the look leaf produces a contact sheet of the fixture variants (and the c41x Development lane) for Ben before it is frozen.

## Open for Ben

- **Who becomes `author` of a copied note?** *Ruled 2026-10-04 by Ben: the literal option — a `copiedFrom` marker, replaced by the editor's identity on the first edit after the copy.* R10 says "whoever edited it after copying". Stateless option (recommended by the research): stamp at copy time — `cp` and Penumbra's paste set `author` to the copier. Literal option: a transient `copiedFrom` key, cleared and replaced by the editor's identity on the first edit. Nothing before the copy/paste work depends on it.
- **c41x's board** places notes at a 200-pt pitch, so 200×200 notes will abut and some extend past their 260-pt lanes. That's a c41x follow-up (re-space at ~216), not a Woodcase change.

## Findings

Under `Sources/Woodcase`.

- **`NoteData` holds only `content`** (Models/PenNode+NoteData.swift:11-17); `PromptData` adds `model`; `ContextData` matches `NoteData`. Pen declares `Note|Prompt|Context extends Entity, Size, TextStyle` and no `CanHaveGraphics` (local/Pen-Schema-2.20.md:180-182, :145-158). Per-kind sites to extend: KindCoding.swift:36-38, NodePropertyCodec+JSON.swift:95,124-126, EditOperation+Codable.swift:54-59,110, PenVariableResolver.swift:636-663, PropertyDiff.swift:246-262 and :373-378 (which also drives claimed keys, PenNode+ClaimedKeys.swift:23-27 — so a note's `width` lands in extras today and `set` refuses it), ChangeCategory.swift:150. Property shapes are keyed by field name (NodePropertyCodec+Shapes.swift:136-158), so same-named fields get schema rows free.
- **Layout gives notes 0×0** (`extractLeafWidth/Height` default `.fitContent(nil)`, PenLayoutEngine.swift:416-445).
- **Metadata** is `PenMetadata {type, extensions}` (flat on the wire); Pen allows arbitrary keys. Deep-key writes exist (NodePropertyCodec+DeepKeys.swift:38), **but reads don't**: `value(at:)` (NodePropertyCodec.swift:73-81) goes straight to `commonPaths`, so `--props common.metadata.leaf` prints nothing (TreeView.swift:312-321 swallows the error) and PropertyColumnWarning.swift:43 fires.
- **Write checks** belong in `checkAuthored` (NodePropertyCodec+Authoring.swift:28-43), the authoring-only funnel; load stays lenient.
- **Notes are skipped** by CG (PenRenderer.swift:243) and RapidPro (`isNonVisual`, RenderNodeProducer.swift:93, :184-190).
- **What Pen and c41x write:** Pen saves unsized notes as `width: 0, height: 0`; Pen strips undeclared keys on load (project/2026-09-26-what-pen-drops-from-a-file.md). c41x's 13 notes carry only `id, name, x, y, content` (147–228 characters) and `metadata {type: postit, kind, author: claude, state: open, leaf?, stage}`.

## Design

**Model.** Note, Prompt and Context gain `width`, `height` (`PenSizing?`) and the full TextStyle set with `TextData`'s Swift types and CodingKeys; no fills. A note whose resolved width or height is ≤ 0 or absent lays out at `PenPostIt.Style.defaultSize` (200) per axis — in layout, so `tree`, hit-testing and `canvasRects` agree. Prompt and context keep 0 when unsized. Lint `note-unsized` (info) suggests writing the size.

**Convention** (`Models/PenPostIt+Convention.swift`): `typeValue = "postit"`; key constants `type, kind, state, author, leaf, stage, tint`; `enum Kind: String { question, answer, reference }`; `enum State: String { open, resolved }`; `struct Metadata { kind, state, author, leaf, stage, tint: PenHexColor? }` parsed leniently into `Field<T> = .valid(T) | .unrecognized(String)`; `PenPostIt.Metadata(node)` is nil unless `metadata.type == "postit"`. `checkAuthored` gains a metadata branch after deep-key folding: refuse a misspelled kind or state with the closest spelling and a stable code, refuse a malformed tint, pass untouched legacy values through. `add -F` routes through it. DocC "The post-it convention" and `woodcase schema postit`.

**The look, v1** (`PenPostIt.Style.standard`, public, Friendly; `fs` = the note's fontSize, default 13):

| Part | v1 |
|---|---|
| Plate | the note rect; corner radius 4; fill = tint (default `#FFF59D`) |
| Shadows | two outer `PenEffect`s: (0,1) blur 2 `#0000001F`; (0,3) blur 10 `#00000024`; spread 0 |
| Inset | 1.0 × fs all sides |
| Body | the note's TextStyle; family default `PenTextMeasurer.defaultFontFamily`; lineHeight default 1.3; top-aligned |
| Ink | `#1C1C1E` @ 0.88 if tint luminance > 0.36, else `#FFFFFF` @ 0.92 |
| Author | bottom-left at the inset; 0.8 × fs, normal weight; ink @ 0.5; one line, ellipsis |
| Body box | H − 2·inset − (author line + 0.5·fs) with an author, else H − 2·inset |
| Overflow | body clipped to its box; when it overflows (decided in Woodcase via `PenTextLayout.overflows`), a 1.2·fs rectangle at the bottom with a tint@0 → tint@1 gradient |
| Resolved | tint mixed 55% toward `#E7E7E7`; first shadow only; body ink @ 0.45; "Resolved" in the author style, bottom-right |
| Empty | author only |
| Inherited | the note's opacity, rotation, flips, enabled |

**Expansion.** `PenPostIt.expansion(of: PenNode, size: PenRect) -> Expansion { root: PenNode; rects: [String: PenRect] }`: a frame with the **note's id** (common minus metadata, `layout: none`, `clip: true`, fill, radius, shadows) and children text `<id>/postit-body`, rectangle `<id>/postit-fade` (only when overflowing), text `<id>/postit-author`, text `<id>/postit-resolved`, with explicit parent-local rects. CG renders it at PenRenderer.swift:243 via `renderNodesIteratively([exp.root], layoutRects: exp.rects, …)`; RapidPro walks it with the note's `parentLocalToWorld`. `paintedExtent(.note)` returns the expansion's painted extent, shadows included. Text goes through `PenTextLayout` ([2026-10-04-text-layout-design.md](2026-10-04-text-layout-design.md)); Penumbra's caret engine lays out `postit-body`'s text in its rect.

**CLI.** `value(at:)` reads deep keys (absent → null), fixing metadata columns in `tree`/`find`. A `woodcase postits <file> [--kind] [--state] [--author] [--leaf] [--stage] [--json]` verb lists id, address, kind, state, author, leaf, stage and the first line of content, with typed filters that refuse misspellings.

## Plan

`job import project/2026-10-04-post-it-design.md --parent SuCn6G`.

```yaml
tasks:
  - title: "Probe Pen.app on note keys"
    ref: p-probe
    desc: "Design: project/2026-10-04-post-it-design.md, decision 2. Using a scratch copy of ../c41x/design/whiteboard/c41x-system.pen and `pen interactive` (method in project/2026-09-26-what-pen-drops-from-a-file.md), find what survives a Pen load and save. Record findings in a dated project doc. Doc only."
    criteria:
      - "The doc reports whether metadata.tint, a note fill, width/height and fontSize survive a Pen load and save"
      - "The doc records how Pen draws a 0×0 note and a sized one, with a reference PNG"
  - title: "Sized notes in the model, codec and layout"
    ref: p-model
    desc: "Design: project/2026-10-04-post-it-design.md, Model. Models/PenNode+{Note,Prompt,Context}Data.swift, Sync/PropertyDiff.swift, PenVariableResolver.swift, Editing/ChangeCategory.swift, Editing/NodePropertyCodec+JSON.swift, Editing/EditOperation+Codable.swift, PenLayoutEngine.swift:416-445, Lint (note-unsized). Coordinate: another agent may be editing EditOperation switches for the three-way diff (leaf BExeMG) — rebase onto it."
    criteria:
      - "add and set accept width, height and every TextStyle key on a note, and tree reports 200×200 for an unsized note"
      - "c41x-system.pen round-trips byte-identical"
      - "An instance override of a note's fontSize applies"
  - title: "The post-it convention, typed and validated"
    ref: p-convention
    desc: "Design: project/2026-10-04-post-it-design.md, Convention and decision 2. New Models/PenPostIt+Convention.swift, Editing/NodePropertyCodec+Authoring.swift, DocC article, the schema table."
    criteria:
      - "set common.metadata.kind=questoin on a postit is refused with a stable code and a suggestion, and so are a bad state and a bad tint"
      - "A file holding misspellings still opens"
      - "woodcase schema postit lists the keys and spellings"
      - "A public test reads kind, state, author and tint as typed values"
  - title: "Metadata columns and the postits verb"
    ref: p-cli
    blockedBy: [p-convention]
    desc: "Design: project/2026-10-04-post-it-design.md, CLI. Editing/NodePropertyCodec.swift:73, WoodcaseCommandCore/Reports/PropertyColumnWarning.swift, new Verbs/PostitsCommand.swift. Follow project/agents/cli-design.md."
    criteria:
      - "tree --props common.metadata.leaf prints values"
      - "woodcase postits on c41x-system.pen --state open --kind question lists its open questions"
  - title: "The Post-it look via the expansion"
    ref: p-look
    blockedBy: [p-model, p-convention]
    desc: "Design: project/2026-10-04-post-it-design.md, The look, Expansion, decisions 3–4. New Rendering/PenPostIt+Style.swift and +Expansion.swift, PenRenderer.swift:243, PenLayoutEngine+PaintedExtent.swift, Lint/DocumentLinter+TextOverflow.swift, a postit fixture (default, 0×0, dark tint, resolved, no author, overflow, rotated, 13 pt, 20 pt) with a reference PNG. Text through PenTextLayout if lHhvYV's 'PenTextLayout: lines placed in a box' has landed; otherwise through PenTextLines and leave the swap to FK9R6M. Produce a contact sheet PNG of the variants plus the c41x Development lane for Ben, and do not treat Style.standard as frozen until he approves (the integrator asks him)."
    criteria:
      - "shot and render draw all 13 c41x post-its with author and tint (one tinted in a scratch copy)"
      - "Overflowing notes are clipped with the fade and linted"
      - "The expansion is public and its parts are listed in the Style docs"
      - "A contact sheet of the fixture variants exists for Ben's review"
```
