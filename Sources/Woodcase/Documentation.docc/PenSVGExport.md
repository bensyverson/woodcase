# Exporting a Selection: SVG and Multi-Root PNG

Draw any set of nodes — under one parent or many — as an SVG or a PNG, each exactly where
the canvas draws it.

## Overview

A selection on the canvas can span parents: a button in one card and a label in another.
Copying it as a picture means drawing each node as it appears on the canvas — through
every ancestor's position, turn and flip, and cut by every ancestor frame that clips —
and nothing else. Woodcase draws that two ways from one seam:

- ``PenRenderer/render(_:layoutRects:rootNodeIDs:bounds:scale:colorSpace:imageProvider:postIt:)``
  — a PNG-ready `CGImage`, usually at 2x for a clipboard.
- ``SVGExporter/data(_:layoutRects:rootNodeIDs:bounds:imageProvider:postIt:)`` — an SVG
  document, vector and editable.

Both resolve the roots through the same walk, so they agree on where every root lands and
what cuts it. The roots draw in the canvas's paint order, whatever order they were named
in; a root inside another root is drawn once, by its ancestor; an id the document lacks is
skipped. An ancestor contributes its placement and its clip, never its paint, opacity,
blend mode or effects: a node copied out of a half-transparent card is the node at full
strength.

```swift
let document = PenVariableResolver.resolve(PenRefExpander.expand(parsed))
let rects = PenLayoutEngine.layout(document)
let selection = ["card-a/button", "card-b/label"]

// Everything the selection paints, shadows and overhangs included.
let bounds = PenLayoutEngine.canvasPaintedExtent(of: selection, in: document, layoutRects: rects)!

let png = PenRenderer.render(document, layoutRects: rects, rootNodeIDs: selection, bounds: bounds, scale: 2)
let svg = SVGExporter.data(document, layoutRects: rects, rootNodeIDs: selection, bounds: bounds)
```

`bounds` is in canvas points; the SVG's `viewBox` is exactly it, one unit per point, and
the PNG is `bounds × scale` pixels, rounded up. `woodcase shot --svg` writes the one-node
form, ``SVGExporter/data(_:layoutRects:rootNodeID:region:imageProvider:postIt:)``, framed
in the node's parent's frame as `shot` frames a PNG.

## What the SVG Says

The SVG writer walks the tree in the CG renderer's paint order and draws every outline from
the renderer's own `CGPath`, so an arc, a smoothed polygon corner or a per-corner radius is
never re-derived from SVG's own primitives.

| Pen | SVG |
|-----|-----|
| Frame, rectangle, ellipse, polygon, path, line | `<path>`, placed by a `matrix()` on its `<g>` |
| Rotation and flip | the node's `<g transform="matrix(…)">` |
| Solid fill | `fill` and `fill-opacity` |
| Linear and radial gradient | `userSpaceOnUse` gradient; its `gradientTransform` is the renderer's gradient frame, so the stops land on the box where Pen puts them |
| Image fill | the pixels, embedded as PNG, placed by mode and crop, clipped to the shape |
| Stacked fills | one element per fill, bottom to top |
| Centered stroke | an SVG stroke at its width, join, cap and a miter limit of 10 |
| Inner and outer stroke | an SVG stroke at twice its width, clipped to the shape or masked to its complement |
| Per-side stroke, zero-area box stroke | the stroke's ring, filled even-odd |
| Dashed stroke (``PenNode/strokeDash``) | `stroke-dasharray` and `stroke-dashoffset` on the stroke, along the renderer's outline, which starts where SVG starts each shape; a paint filled through the outline fills the dashed one |
| Frame `clip` | a `clipPath` on its children |
| Opacity | the node's `<g opacity>` |
| Blend mode | `mix-blend-mode` on the node's or fill's element |
| Outer shadow | a filter on the node's silhouette: blur, offset, flood, knocked out under the silhouette |
| Inner shadow | a filter on the silhouette's complement, kept inside it |
| Layer blur | `feGaussianBlur` on the node's `<g>`, sigma half the radius |
| Text | real `<text>`, one `<tspan>` per styled run per line |
| Icon | its glyph's outline, as a `<path>` |
| Instance | its expanded subtree (expand the document first) |

A shadow's offset is written as authored, in the node's own coordinates, so it turns and
flips with the node and its ancestors, as Pen and the CG renderer cast it. (Before leaf
`u7pRBs` it was carried back through the inverse of the placement to stay on the screen's
axes; that matched the CG renderer's old screen-fixed shadows, and was wrong for Pen.)

### Text

Text stays text, so it can be edited and searched. The lines are ``PenTextLayout``'s, the
ones the CG renderer draws: each run sits at the `x` Core Text set it at, on its line's
baseline, and names its family, size, weight, style, letter spacing and decorations. The
reader sets the glyphs inside a run with its own copy of the font. That is the fidelity it
costs: where the reader lacks the font it substitutes one, and that run's width drifts —
but only that run's, because the next run and the next line start where they should, and a
paragraph still breaks where it breaks on the canvas. Optical sizing is off on every run, so
a variable font with an `opsz` axis is set at its default optical size, as Core Text sets it.
Outlining the glyphs instead would be exact everywhere and editable nowhere; icons are
outlined, because an icon font is never installed where the SVG is opened.

### What SVG Cannot Say

These degrade, on purpose:

- **Angular and mesh gradients.** SVG has no conic or mesh paint. The paint is embedded as
  the CG renderer's picture of it through the shape, at ``SVGExporter/rasterScale``.
- **Notes, prompts, contexts, browser placeholders, connections.** Embedded as the CG
  renderer's picture of the node.
- **Background blur.** SVG cannot read what lies behind an element (`BackgroundImage` was
  never implemented by browsers). The node draws; the backdrop is not blurred.
- **Shader fills.** Not drawn, as in the CG renderer.
- **Linear burn and linear dodge.** CSS has neither; they blend as `color-burn` and
  `color-dodge`, where the CG renderer uses multiply and screen.
- **A group's silhouette** is built from its descendants' outlines, as Pen casts it; a
  descendant's own clip does not cut it.

## How Close It Is

`SVGExportWebViewTests` rasterizes the SVG of every top-level node of 21 render fixtures in
WebKit — the headless page SleepyHollow hosts for the suite — and measures it against the
CG render of the same region, both at 2x. Measured 2026-10-14 with
`swift test --filter SVGExportWebViewTests`:

| Fixture | MAE |
|---------|-----|
| render-shapes-and-fills, -gradients, -strokes-and-paths, -clipping-and-gradients, -arc-donut, -per-side-strokes, -painted-lines, -angular-shapes, -mesh-gradients | 0.000 |
| render-free-groups | 0.008 |
| render-image-crops | 0.029 |
| render-rotated-free | 0.045 |
| render-transforms-and-effects | 0.068 |
| render-text-fills | 0.152 |
| render-shadows | 0.153 |
| render-group-shadows | 0.187 |
| render-text | 0.236 |
| render-inner-shadow-shapes | 0.252 |
| render-stroke-fills | 0.439 |
| render-icon-placement | 0.656 |
| render-background-blur | 1.646 |

The zeros are real: WebKit on macOS paints SVG through Core Graphics, so a path filled with
a color or a gradient lands on the pixels the CG renderer's does. What remains is glyph
rasterization (Core Text draws a glyph, WebKit fills its outline), SVG's filter blur against
CG's shadow blur, and background blur, which the SVG cannot draw.

Two WebKit behaviors the export works around, found by that suite: an
`feComponentTransfer` alpha table over `SourceAlpha` draws nothing, so an inner shadow's
inverse is a flood composited `out` of the silhouette; and WebKit picks a variable font's
optical size from the size it lays SVG text out at internally, which set 14 pt Inter in its
narrow display cut (`render-text` measured 5.08 before optical sizing was turned off).

## Topics

### Exporting

- ``SVGExporter``
- ``PenRenderer``
