# Stroke paints: gradients and images on strokes (2026-09-26)

Author: Claude (Opus 5.5), leaf `D3TIGo` under `b3HCbu`, for Ben. Leaf 4 of
[the text and stroke fills report](2026-09-26-text-and-stroke-fills.md); built on the clip/domain seam of
[the fill clip and domain follow-up](2026-09-26-fill-clip-and-domain.md), without disturbing the per-side alignment of
[the gradient geometry follow-up](2026-09-26-gradient-geometry-and-per-side-strokes.md). Everything about Pen here is
established from its **renders** (`pen` CLI 0.3.9, headless, format 2.19), never from its source.

## What Pen does (confirmed on a committed fixture)

The fills report's finding 2 holds on the new fixture board for board: a stroke's paint is laid out over the
**node's box** for every alignment and every shape. A gradient pads beyond the box (so an outer stroke's outer band
shows the end colors), and an image is drawn only where the placed image is: an outer stroke painted with a
`stretch` or `fit` image draws nothing, and with a `fill` image only the side bands the covering image overhangs show
(the image covers x 40…280 of a 200 × 120 box at x 60…260; the top and bottom bands fall outside it). A centered image
stroke shows only its inner half, for the same reason.

## What changed in Woodcase

- `PenStrokeRenderer.renderStroke(_:path:rect:roundedBox:in:imageProvider:)` takes the node's box (`rect`) as the
  paint domain and the renderer's image provider. Its region is a filled path handed to
  `PenFillRenderer.renderFills(_:clip:fillRule:domain:in:imageProvider:)`:
  - uniform width: `path.copy(strokingWithWidth:)` at the width (center) or twice it (inner, outer), miter limit 10,
    filled non-zero, inside the same alignment clip the solid path uses (the shape for inner, its even-odd complement
    for outer — its bounds widened to take in the outline's miter tips);
  - per-side width on a box: the ring from `PenStrokeRenderer+PerSide`, filled even-odd;
  - per-side width on any other shape: the old inner-bands fallback, now a union of band rectangles clipped to the
    shape (so a translucent paint no longer double-covers the corners).
- A stroke that is **exactly one solid color with no blend mode** keeps `strokePath()`, so its pixels do not move.
  Everything else — gradients, images, stacks, a disabled layer, a blended solid — goes through the fill seam, which
  draws every enabled fill bottom to top. Before, only the first solid color of a stroke was drawn at all.
- Lines pass their box too (`renderLine`), and the browser placeholder passes its rect.
- **A seam bug, fixed in `PenFillRenderer+Gradient`:** the angular gradient's bitmap covered only the domain, so an
  angular paint seen through a clip that reaches past the box (an outer or centered stroke) was cut off at the box
  (`rect-angular-center` MAE 6.86). The bitmap now covers the domain grown by the clip's path bounds
  (`boundingBoxOfPath`, so curve control points do not grow it); for every shape fill the clip lies inside the domain
  and the bitmap is unchanged.

## Figures

Fixture: `Tests/WoodcaseTests/Fixtures/render-stroke-fills.pen` + `images/uv-map.png`, written by
`scripts/gen-paint-geometry-fixtures`; references by `scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-stroke-fills.pen --scale 2`.
Figures from `swift test --filter PenStrokeFillTests` (each test prints them), node box x 60…260, y 60…180 (the path's
box is y 60…160). Ramp fits are the least-squares fit of `PenFillDomainTests.RampFit`; UV fits are `u = R/255` and
`v = G/255` over the stroke eroded by two pixels, whose ends sit half an image pixel inside the box (≈ 60.39 / 259.61
on x, ≈ 60.47 / 179.53 on y).

| Board | MAE before → after (2x) | Woodcase stop 0 → 1 | Pen stop 0 → 1 |
|---|---|---|---|
| rect-lin-h inner / center / outer | 7.65 / 8.50 / 9.35 → 0.02 / 0.01 / 0.01 | 59.98→260.01 / 60.01→259.98 / 60.00→260.00 | 59.99→260.00 / 60.00→259.99 / 60.00→259.99 |
| rect-lin-v-outer (y) | 9.35 → 0.00 | 60.00 → 179.99 | 59.98 → 179.98 |
| rect-lin-h-outer-radius | 8.62 → 0.02 | 59.99 → 260.00 | 60.00 → 259.99 |
| rect-lin-h-center-filled | 8.48 → 0.01 | 60.01 → 259.98 | 60.00 → 259.99 |
| ellipse-lin-h-outer | 7.45 → 0.07 | 59.99 → 260.00 | 60.00 → 260.00 |
| path-lin-h-center | 4.44 → 0.03 | 59.98 → 260.04 | 59.99 → 260.02 |
| frame-perside-lin-h unset / inner / outer | 7.04 / 6.48 / 7.60 → 0.01 each | 59.99→260.00 / 60.00→260.00 / 60.00→259.99 | 60.00→259.99 / 60.00→260.00 / 60.00→259.99 |
| rect-uv inner / center | 7.65 / 4.04 → 0.01 / 0.00 | u 60.35→259.61 / 60.34→259.59 | u 60.37→259.59 / 60.34→259.59 |
| ellipse-uv-center, path-uv-center | 5.41, 4.14 → 0.04, 0.02 | u 60.36→259.60, 60.37→259.59 | u 60.37→259.59, 60.37→259.59 |
| frame-perside-uv, -uv-radius | 4.24, 4.40 → 0.00, 0.00 | u 60.37→259.58, 60.36→259.59 | u 60.38→259.58, 60.37→259.58 |
| rect-uv-outer, rect-uv-fit-outer | 0.00 → 0.00 | nothing drawn | nothing drawn |
| rect-uv-fill-outer | 3.19 → 0.00 | side bands only | side bands only |
| rect-radial-center, rect-angular-center | 25.50, 12.75 → 0.01, 0.02 | | |
| rect-stack, rect-blend-multiply, rect-grad-opacity | 6.37, 12.75, 5.10 → 0.03, 0.00, 0.02 | | |

Every fitted stop is within 0.1 pt of Pen's and of the box edge (the test's bound is 0.5 pt).

**Solid strokes unchanged.** Every MAE the full suite prints was captured before (`swift test --quiet` on this
branch's base, `aa4f0dd`, with only the new test file added) and after: all 143 figures of the before run —
`render-strokes-and-paths` 5.114, `render-shapes-and-fills` 0.016, `render-gradients` 0.133,
`render-clipping-and-gradients` 0.060, `render-transforms-and-effects` 1.122, the per-side, gradient-geometry and
fill-domain cases, the banking and Pen-app screens — are identical at the precision each test prints. The eleven
WebView comparisons failed to start in the before run (`WKErrorDomain Code=1` under load); after, they match
`performance/mae-baseline.csv` exactly.

## Not done here

- Mesh gradients and shader fills on strokes draw nothing, as on shapes; once `PenFillRenderer` draws a mesh, strokes
  get it through the same seam with no change here.

  > **Correction (2026-09-26):** `PenFillRenderer` already drew meshes (`a679ff1`) when this landed, so mesh strokes
  > draw through the seam today (checked with `woodcase render` on a 20 pt inner mesh stroke). Shader strokes still
  > draw nothing. No Pen reference pins mesh strokes yet.
- An outer *solid* stroke's complement clip still spans the path's box grown by twice the width, so a very sharp miter
  tip beyond that is clipped — kept for pixel identity; the painted path widens the clip to the outline's bounds.
- Per-side widths on ellipses, paths and polygons remain the fallback bands (finding 8 of the geometry follow-up).
