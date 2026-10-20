# Pen Interoperability

Rendering behavior differences between the format's own editor and standard SVG/CSS, and how Woodcase handles them.

## Overview

Woodcase aims to render `.pen` files as closely as possible to the output of the format's own editor. However, that editor's renderer diverges from the SVG and CSS specifications in several ways. This article documents those differences, explains how Woodcase handles each one, and notes areas where residual rendering gaps remain.

These findings were established through pixel-level snapshot testing that compares Woodcase's rendered output against reference PNGs exported directly from the format's own editor.

## Path Geometry Normalization

The most significant difference is how the format's own editor interprets SVG path geometry on `path` nodes.

**Standard SVG behavior:** Path coordinates are absolute — `M 10 10 L 50 50` draws from pixel `(10, 10)` to pixel `(50, 50)`, regardless of the node's declared `width` and `height`.

**The editor's behavior:** With no `viewBox`, path geometry is normalized to fill the node's declared dimensions. The editor computes the path's bounding box, translates it to the origin, and scales each axis independently to match the node's `width` and `height`. This is equivalent to SVG's `viewBox` attribute with `preserveAspectRatio="none"` fitted around the tight bounding box. Its UI calls this Vector → Viewbox → *Auto*.

For example, given this node:

```json
{
  "type": "path",
  "width": 200,
  "height": 200,
  "geometry": "M 10 10 L 50 10 L 50 50 L 10 50 Z"
}
```

The geometry defines a 40×40 square at offset `(10, 10)`. The editor renders this as a 200×200 square filling the entire node — the path is translated to the origin and scaled 5× in both axes.

### Edge Cases

| Scenario | The editor's behavior |
|----------|-------------------|
| Zero-height path (horizontal line) | Only the x-axis is scaled; y-coordinate is translated to the node's top edge |
| Zero-width path (vertical line) | Only the y-axis is scaled; x-coordinate is translated to the node's left edge |
| Single-point path | Translated to the node's origin, no scaling |

### Explicit viewBox

A `path` node may instead declare a ``PenViewBox`` — the wire form is the SVG-style array `[x, y, width, height]`, and the editor's UI calls it Vector → Viewbox → *Fixed*. The named region is mapped onto the node box: the geometry is translated by `(-x, -y)` and scaled by `nodeWidth / width` and `nodeHeight / height`.

Three things follow, all confirmed against version 1.2.7 of the format's own editor rendering `Tests/WoodcaseTests/Fixtures/v2.17/viewbox-experiment.pen`:

- **The stretch is non-uniform.** A `[0, 0, 100, 100]` viewBox on a 200×100 node doubles the geometry horizontally and leaves it alone vertically; aspect ratio is not preserved. There is no `preserveAspectRatio` equivalent in the format.
- **The tight bounding box is ignored.** Geometry is placed at its own coordinates within the region, so a triangle spanning 10–90 in a `[0, 0, 200, 200]` viewBox sits 10 px inside a 200 px node instead of filling it.
- **Overflow is drawn, not clipped.** A `[25, 25, 50, 50]` viewBox on a 200×200 node scales 4× and the geometry runs past the node box on every side; the editor draws all of it. Only an ancestor's own `clip` cuts it off. Its PNG export bounds grow to contain the overflow.

A viewBox whose `width` or `height` is not positive cannot be mapped and falls back to the default tight-box normalization.

### Woodcase Implementation

Woodcase matches the editor's behavior in both modes. The mapping is ``PenPath/mapped(onto:viewBox:)``, computed without CoreGraphics so the renderer and the code emitters share it; `PenShapeBuilder` only draws the result. Stroke thickness is **not** scaled — only the path geometry is transformed. The React emitter passes an explicit viewBox straight through to the `<svg>` element, adding `preserveAspectRatio="none"` and `overflow="visible"` so the browser reproduces the same mapping.

## Stroked Path Positioning

When a path node has a thick stroke, the format's own editor and Woodcase produce slightly different positioning. Both normalize the path geometry to fill the node's box, and both allow the stroke to overflow the box bounds. But they differ in **what is aligned** to the box:

**Woodcase:** Aligns the **path geometry** to the box. The stroke overflows symmetrically in all directions. This matches standard SVG behavior.

**The editor:** Appears to rasterize the path and stroke together into a bitmap first, then align the **bitmap's top-left corner** to the box position. Because the stroke extends the bitmap beyond the path geometry, the visible path content is shifted down and to the right by however far the stroke extends above and to the left of the path. For a simple thick stroke this is roughly `stroke_width / 2`, but miter joins on sharp angles can extend much further — the offset depends on the stroke's actual rendered extent, not just its thickness.

Woodcase does not replicate this offset, as it appears to be an artifact of the editor's rasterization pipeline rather than intentional behavior. This is the primary contributor to the higher MAE on stroke-heavy fixtures (~5.0). If a future version of the editor changes this behavior, the MAE should improve without changes on our side.

> **Corrected 2026-09-27 (leaf `onFiTm`):** the explanation above was wrong. The ~5.0 MAE came from a stale reference, not from a bitmap offset in the editor: `render-strokes-and-paths`' PNG had been exported on 2026-03-23 by an older Pen that left a path's geometry at its SVG offset. Re-exported from today's Pen (`scripts/pen-oracle`, commit `89e43e8`), the fixture measures 0.027 against the Core Graphics renderer, which aligns the path geometry to the box exactly as today's Pen does. There is no stroked-path offset to replicate.

## Stroke Alignment Default

In .pen 2.17 the `strokeAlignment` key defaults to `"center"`, and the format's own editor omits it on save whenever the stroke is centered. Woodcase follows suit: an absent `strokeAlignment` renders centered.

> Note: This reverses the 2.9 default. The legacy nested `stroke.align` defaulted to `"inside"`, which made strokes on open paths (lines, unclosed SVG paths) invisible unless `align` was set to `"center"` explicitly. ``PenStrokeMigrationRule`` carries every legacy `align` across verbatim — `inside` → `inner`, `outside` → `outer` — so no legacy document changes appearance; only newly authored 2.17 nodes get the centered default.

## Files From a Newer Editor

The format's own editor migrates a file on load according to the version it declares — version 1.2.14 of the editor, which writes 2.19, turns every inner shadow in a pre-2.19 file into an outer one. So the declared version is data, not a label: Woodcase writes back a newer minor's declared version unchanged rather than stamping its own model's older one, and treats a file of another major as read-only. The whole policy is in <doc:PenEngine>, under *The version gate*.

Woodcase models and writes 2.20, the format version 1.2.15 of the editor writes, and migrates an older file the way the editor does: every pre-2.19 inner shadow becomes an outer one — which is what every earlier editor drew — with a diagnostic naming the node, and `spread`, which 2.19 removed, moves into `metadata.woodcase.shadowSpread` (see *Miter Limits and Shadow Spreads Live in Metadata*, below); and a pre-2.20 image paint's `fill`/`fit` mode becomes `cover`/`contain`, and a missing one an explicit `stretch`. The editor does all of it silently. See <doc:PenEngine>, *Shadows before 2.19* and *Image modes before 2.20*.

## Dashed Strokes Live in Metadata

.pen 2.10 allowed a `dashPattern` (and a `miterAngle`) inside the nested stroke object. Neither survives in 2.17 — the format's own editor (version 1.2.7) strips a dash pattern silently on save. Woodcase keeps a dash in the node's `metadata.woodcase` instead (Ben's ruling, 2026-10-14): `strokeDash`, the dash and gap lengths, and `strokeDashOffset`, the phase (``PenStrokeDash``). The editor keeps both keys on save — probed with its headless CLI (pen 0.3.11, 2026-10-15) on a frame, rectangle, ellipse, path, line and polygon, each edited before saving — and draws the stroke solid; every Woodcase target dashes it (<doc:PenRendering>, *Dashed strokes*). Migrating a legacy document moves a `dashPattern` into `strokeDash`; one no target can draw, or on per-side widths, is discarded with a ``PenDiagnostic`` at the ``PenDiagnostic/Stage/migration`` stage naming the node.

## Miter Limits and Shadow Spreads Live in Metadata

Two more values the format dropped come back the same way (leaf `zRp9CO`, wave E0 of Penumbra's `project/2026-10-14-feature-enhancements-plan.md`):

- **`strokeMiterLimit`** — the longest a mitered join reaches, in stroke widths, before it is beveled (``PenNode/strokeMiterLimit``). Absent, it is **4**, the limit the editor strokes with: its headless CLI (pen 0.3.11, 2026-10-15) bevels the 25° apex of an 8 pt stroked triangle (a miter of 4.62 widths) and miters a 40° one (2.92). Until this leaf the CG renderer and SVG export stroked with CoreGraphics' 10 while painted extent assumed 4, so Woodcase drew a 25° apex mitered where the editor beveled it; 4 is now every target's default. A 2.10 `miterAngle` migrates to the limit it stands for, 1 / sin(angle / 2). The editor keeps the key and strokes with 4 regardless.
- **`shadowSpread`** — how far each shadow is grown before it is cast, as CSS's `box-shadow` spread (``PenShadowSpread``). The editor refuses a shadow carrying `spread` since 2.19, so the value sits beside the effects, one entry per spread shadow: `{effect, spread, shadow}` — the shadow's place among the node's effects, the spread in points, and the shadow it was made for. The editor keeps the entries on save (probed on a rectangle, text and path, pen 0.3.11, 2026-10-15) but cannot see them, so when it changes, moves or removes the shadow the entry no longer matches what sits at its place and is ignored — the shadow casts without spread rather than spreading the wrong one — and lint reports it (`shadow-spread-stale`). The match ignores what the editor rewrites in a shadow it has not changed: on save it writes a lone effect in an array as the object itself, and writes `"color": "#000000"` into a shadow that names none, which is also the color it draws one in (``PenShadowSpread/matches(_:)``). A pre-2.19 `spread` migrates into an entry made for the migrated (outer) shadow.

Both draw in the CG renderer (<doc:PenRendering>); <doc:PenCodeGen> and <doc:PenSVGExport> say which other targets follow.

## A Node's Blend Mode Lives in Metadata

The format gives a blend mode only to paints and shadows (schema 2.17 and 2.20), and the editor drops a node's own top-level `blendMode` when it opens a file: all seven in RapidPro's `group-blend.pen` were gone from the file its headless CLI saved. Woodcase stores a node's blend mode in `metadata.woodcase.blendMode` instead (Ben's ruling, 2026-10-20; leaf TesTbK), which the editor keeps: a rectangle's, a group's beside another Woodcase key, and a text's all survived `pen interactive`'s load and save (pen CLI, 2026-10-20). Callers still read and write it at `kind.blendMode` (``PenNode/blendMode``); a file that writes the old top-level key is read into metadata, and a write never emits it. A paint's and a shadow's `blendMode` stay where the format puts them.

An instance override still writes the raw `blendMode` key into the instance's overrides, which Woodcase reads into the patched node's metadata: a `metadata` override would replace the component node's whole metadata, and a `ref` node's own metadata does not reach its root.

## Underline and Strikethrough Survive the Editor

The editor strips a text node's `underline` and `strikethrough` when it opens a file and draws neither, though both are in its schema; it keeps metadata. Woodcase writes both into `metadata.woodcase.textDecoration` too and restores them from it on its next read (``PenTextDecoration``; <doc:PenRichText>, *Underline and strikethrough survive Pen*), so a save in the editor loses neither. Its headless CLI (pen 0.3.11, 2026-10-15) saves the file as version 2.21, which Woodcase reads as a newer minor and writes back unchanged.

> Corrected 2026-10-15 (leaf `ajB4uc`): this section was titled *Dash Patterns Are Gone* and said Woodcase's model had no dash and its renderer never dashed a stroke; that held from the 2.17 port until dashes moved into metadata.

## Kept Divergences

Where the format's own editor gives an answer Woodcase judges worse, and the difference is small, Woodcase keeps its own and says so here. Each one is a ruling, not a gap to close.

- **Mesh gradients** are subdivided to an error bound rather than a fixed 32 × 32 cells, and blended without 8-bit truncation — see <doc:PenMeshGradients>.
- **A turned child's first layout after load.** The editor fits widths before heights (its flex passes run width-fit, width-fill, height-fit, height-fill, arrange), so on its first layout a turned flow child whose height is not resolved yet — a `fit_content` frame, a `fill_container` height, a turned main-axis fill in a column — is measured at height 0 when its container's width is fitted. Any later relayout (any edit to the container) settles elsewhere, so the editor is not idempotent there. Woodcase lays out the settled answer the first time. From `flex-turned-fill.pen` (rows of padding 10 and gap 10 around two 60×40 siblings): a row of height 120 around a 60-wide `height: fill_container` child turned 90° is 160 wide on the first pass and 260 settled; turned 30°, 211.96 and 261.96; a row around a turned `fit_content` frame (60×40 at 30°) 211.96 and 231.96; a column of height 300 around a `height: fill_container` child turned 30° is 80 wide on the first pass and 161.96 settled. Woodcase gives the settled figure in each (`PenLayoutTurnedFillTests`). A reference layout taken from the editor's first pass (`scripts/pen-oracle`) disagrees on exactly these; `scripts/pen-settle` writes the settled one. Ruled 2026-09-28; see `project/2026-09-28-geometry-model.md`, divergence 3.
- **A ramp across a flat line.** The editor lays a stroke's paint over the node's box, and a flat line's box has no height, so a gradient with any component across the line collapses: a slanted linear ramp draws as its two end colors split along the line, a vertical ramp or a radial gradient as black. Woodcase lays the paint over the stroke's band instead — the stroke's width across the line, the line's length along it — so the ramp shows across the band as a designer means it; along the line, which is the ramp the editor does draw, the two agree (`render-painted-lines-fill-gradients` 0.019 in React, 0.019 in CG). All three targets do the same: the renderer (`PenRenderer.lineBand(_:strokeWidth:)`), React (a full-width line's band is a `<div>` painted by the stroke's fills; a fixed line's SVG paint servers laid over the band) and SwiftUI. `render-painted-lines-fill-degenerate` (`scripts/gen-react-fx-fixtures`, then `scripts/pen-oracle --scale 2`) holds a vertical, a radial and a 45° ramp; it measures 16.297 in the renderer, pinned there (`PenInnerShadowShapesSnapshotTests`), and React (16.296) and SwiftUI (16.255) gate at the renderer's MAE + 1.0. Before, the renderer drew no painted stroke on a flat line at all, and React drew `currentColor`. Kept by Ben's standing ruling of 2026-09-26 (keep behavior that beats the editor's, accept the MAE gap, document it); applied 2026-09-28, leaf `4fZZ38`.

## Snapshot Test Thresholds

Pixel-level comparison between Woodcase and reference images from the format's own editor uses mean absolute error (MAE), computed by PixelPeeper and reported in 8-bit channel steps (0–255): the mean absolute difference of every premultiplied sRGB channel byte, alpha included, so 1.0 means "off by one step on average". When a render and its reference differ in size, both are resampled onto the smaller width and height before comparing. Even with correct behavior, some residual MAE is expected due to:

- **Anti-aliasing algorithms** — CoreGraphics and the editor use different sub-pixel rasterization
- **Sub-pixel rounding** — stroke alignment and path coordinates may round differently

**The margin rule.** Every hardcoded threshold in the snapshot suites — here, `PenSnapshotTests`,
and every other file whose `#expect` pins an MAE — is set from what the renderer actually measures,
not carried forward at a historical ceiling: `max(measured × 1.5, measured + 0.25)`, rounded up to
a hundredth, and never loosened past the threshold it replaces. Where a board scores badly for a
known reason (a documented rendering gap, not just "it's high today"), the bar stays there with the
reason and the measured figure beside it. A single threshold shared across many parameterized
artboards is set from the worst case among them, named in the comment. See
`project/2026-09-26-mae-margin-rule.md` for the full audit (every threshold in the repo, before and
after) and RapidPro's `project/2026-09-26-mae-margin-rule.md` for the same rule applied there.

Current MAE thresholds (`swift test --filter PenSnapshotTests`, 2026-09-26; two runs, identical
measured figures):

| Fixture | MAE | Threshold |
|---------|-----|-----------|
| Shapes and fills | 0.016 | 0.27 |
| Gradients | 0.133 | 0.39 |
| Gradient extras | 0.049 | 0.30 |
| Transforms and effects | 0.886 | 1.33 |
| Clipping and gradients | 0.060 | 0.31 |
| Strokes and paths (reference re-exported with `scripts/pen-oracle`; the old one scored 5.114) | 0.027 | 0.28 |
| blur1 | 0.045 | 0.30 |
| blur2 | 0.082 | 0.34 |
| blur3 | 0.174 | 0.43 |
| blur2-no-bg (group positioning) | 0.000 | 0.25 |
| blur3-no-bg (group positioning) | 0.097 | 0.35 |

**Fonts in the snapshot suites.** Most fixtures set Inter, Pen's default face, and the `layout-text-*` and `woodcase-app` fixtures set IBM Plex Sans. Both are committed under `Tests/WoodcaseTests/Fonts` with their OFL licenses in `LICENSES/`, each the variable file Pen's own Google font table names — IBM Plex Sans as fonts.gstatic.com serves it (v23), not the static cuts (`project/2026-09-28-pen-font-faces.md`, where `scripts/pen-font-audit` compares Pen's whole table with what the Google font resolver picks), and every suite that renders them calls `TestFontRegistration.registerTestFonts()` itself: Core Text registration is process-wide and cannot be undone, so a suite that relied on another suite having registered a face would measure a different font depending on the order the suites ran in. No test reads the user's `~/.woodcase` font cache.
