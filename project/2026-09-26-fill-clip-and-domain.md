# Fill clip and paint domain: what Pen does, and the seam Woodcase now has (2026-09-26)

Author: Claude (Opus 5.5), leaf `EL9llT` under `b3HCbu`, for Ben. Leaf 2 of
[the text and stroke fills report](2026-09-26-text-and-stroke-fills.md); builds on
[the gradient geometry follow-up](2026-09-26-gradient-geometry-and-per-side-strokes.md). Everything about Pen here is
established from its **renders** (`pen` CLI 0.3.9, headless, format 2.19), never from its source.

## Findings

1. **Pen lays every fill over the node's box, whatever the outline.** A red→blue linear ramp on a donut, an even-odd
   path, a hexagon, a triangle, a quarter-pie arc, a curve whose Bézier control points overshoot its box, and a
   `viewBox` path whose geometry sits well inside its box puts stop 0 and stop 1 on the node box's edges every time
   (fitted within 0.04 pt; table below). The fills report found the same for text and strokes, so the box is the
   domain for every surface Pen paints.
2. **Even-odd outlines take every fill type.** Pen draws gradients (and, by the same clip, images) through a donut's
   ring and an even-odd path's ring and leaves the holes empty.
3. **Woodcase got both wrong before this change.** Its paint domain was the outline path's `boundingBox`, which is the
   node box only for rectangles, frames and full ellipses: it was narrower for polygons, arcs and `viewBox` paths, and
   *wider* for curves (CoreGraphics' `boundingBox` includes control points — the curve board's ramp started 20 pt
   above the node). And its even-odd branch drew solid colors only, so a donut or even-odd path with a gradient or
   image fill drew nothing.

Measured on `Tests/WoodcaseTests/Fixtures/render-fill-domains.pen` (node box x 20→220, y 20→140), Pen's 2x export
against Woodcase at 2x, by `PenFillDomainTests` (the Swift fit is a least-squares line of position against
`t = B / 255` over fully covered, unclamped pixels):

| Board | Pen stop 0 → 1 | Woodcase before | MAE before | MAE after |
|---|---|---|---|---|
| donut-h, donut-v (innerRadius 0.5) | box edges | nothing drawn | 23.47 / 23.47 | 0.11 / 0.12 |
| donut-radial | — | nothing drawn | 26.29 | 0.13 |
| evenodd-h (square with square hole) | 20.00 → 220.00 | nothing drawn | 29.88 | 0.08 |
| hexagon-h | 20.00 → 220.00 | 33.40 → 206.60 | 1.54 | 0.08 |
| triangle-v | 19.99 → 139.98 | stop 1 at 109.99 | 4.31 | 0.04 |
| arc-h, arc-v (quarter pie) | box edges | stop 0 at 120.02 / stop 1 at 79.98 | 4.50 / 4.50 | 0.03 / 0.03 |
| curve-v | 19.99 → 139.99 | stop 0 at −20.00 | 6.82 | 0.11 |
| viewbox-h | 20.01 → 219.99 | 70.02 → 169.98 | 2.49 | 0.03 |

After the change every fitted stop is within 0.5 pt of the box edge (the test's criterion).

## What changed

- `PenFillRenderer.renderFills(_:clip:fillRule:domain:in:imageProvider:)` is the one entry point. The **clip** (a
  `CGPath` and a `CGPathFillRule`) is where each fill shows; the **domain** (a `CGRect` in the same space) is what the
  gradient frame and the image placement are computed from. Solid colors still fill the path directly (same pixels);
  gradients and images clip, then draw over the domain. Each fill is clipped separately, which is what finding 6 of the
  fills report asks for.
- `PenShapeBuilder.fillRule(for:)` names the rule an outline is filled with (even-odd for `innerRadius` ellipses and
  `evenodd` paths). `PenRenderer`'s separate solid-only even-odd branch is gone; shapes and frames pass their node box
  as the domain.
- `PenFillRenderer` is split by purpose: `+Gradient`, `+Angular`, `+Image` (with `imageRect(mode:imageSize:in:)`).

## Existing fixtures

Every MAE the suite prints was captured from a full `swift test` run on this branch's base (`155eef2`) and on this
change: 139 distinct ids — `render-shapes-and-fills` 0.0158, `render-gradients` 0.1329, `render-clipping-and-gradients`
0.0603, `gradient-extras` 0.0486, `render-strokes-and-paths` 5.1138, `render-transforms-and-effects` 1.1222, the blur,
viewBox and icon fixtures, all 72 gradient-geometry and 26 per-side stroke cases, the banking and Pen-app screens and the
WebView comparisons. **Every one is identical to four decimals.** None of those fixtures has a non-solid fill on an
outline whose `boundingBox` differs from its box, or on an even-odd outline; `render-fill-domains` is the first that does.

## Known gaps, not addressed here

- An ellipse with both a partial `sweepAngle` and an `innerRadius` is built as a pie plus a *full* inner ellipse, so
  under even-odd the inner ellipse's part outside the pie is filled. That is `PenShapeBuilder`'s outline, unchanged by
  this leaf, and was not probed against Pen.

  > **Fixed 2026-09-26 (leaf LlN8Is).** Probed against Pen (`Fixtures/render-arc-donut.pen`): Pen draws an arc donut
  > as one closed ring with straight cuts along the start and end angles, and never fills the inner ellipse outside
  > the sweep. `PenShapeBuilder` now builds exactly that ring; `PenArcDonutTests` holds five boards at MAE ≤ 0.13.
- Mesh gradients and shader fills still draw nothing; the seam gives them a domain when they are built.
