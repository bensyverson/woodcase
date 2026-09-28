# Gradient geometry and per-side stroke alignment: what Pen does (2026-09-26)

Author: Claude (Opus 5.5), leaves `UoumNa` (gradients) and `yKT5m9` (per-side strokes) under `b3HCbu`, for Ben.
Follows [the fills report](2026-09-26-text-and-stroke-fills.md), which found rotated linear gradients with a
centre/size and angular gradients off by MAE 11.5 and 12.4 on plain rectangles (open question 5, decision 5) and per-side
strokes always drawn inside (finding 5). Both are fixed; this is what Pen turned out to do. Everything here is
established from Pen's **renders** (`pen` CLI 0.3.9, headless, format 2.19), never from its source.

## Findings

1. **Pen lays out every gradient type in the node's normalised box.** In the gradient's own space the paint is centred
   on the origin with unit extent. That space is scaled by `size` (width on its x axis, height on its y axis, default
   1), rotated counter-clockwise on screen by `rotation`, moved to `center` (a fraction of the box, default ½, ½), and
   only then stretched to the box. As an affine map from gradient space to user space:
   `scale(size) → rotate(−rotation) → translate(center) → scale(box.width, box.height) → translate(box.origin)`
   (y down, so `rotate(−θ)` turns counter-clockwise on screen). On a square box this is what anyone would expect; on a
   400×120 box a 45° linear gradient runs at 73.3° on screen, not 45°, and radial and angular gradients are ellipses.
2. **Linear:** stop 0 at `(0, ½)`, stop 1 at `(0, −½)` — bottom to top at rotation 0, and `size.height` is the ramp's
   length as a fraction of the box. `size.width` has no effect (Pen's own re-save drops it from linear gradients).
   Fitted on a 400×120 rect: rotation 45 → ramp direction 253.30°, length 162.55 pt, both exactly the model's
   (`(−sin r / W, −cos r / H)`); `center (0.3, 0.4)` at rotation 30 → t(box centre) 0.313, the model's 0.5 − 0.1 − 0.0866.
   Least-squares residual 0.0016 in t on every probe.
3. **Radial:** stop 1 on the circle of radius ½, in the same frame. Rotation is *not* a no-op once `size` is
   non-uniform; Woodcase ignored it (MAE 15.3 on `rad-wide-r45-size` before, 0.44 after). Stops pad outward.
4. **Angular:** `t = (atan2(q.y, q.x) + 90°) / 360°` for a point `q` in gradient space: stop 0 points straight up and
   the sweep is clockwise on screen, rotation turning the start counter-clockwise. `size` scales before the rotation
   (the rotate-then-scale order misses by a quarter turn; scale-then-rotate fits to 0.001 in t). A position below the
   first stop or above the last **pads** with the end colour; it does not wrap round the seam. Woodcase took the angle in
   pixel space, so every non-square angular gradient was wrong, and it *extrapolated* below the first stop.
5. **Colours interpolate in gamma-encoded sRGB**, as CoreGraphics does (red→green at t = ½ reads (128, 126, 0)).
6. **Per-side stroke widths honour `strokeAlignment`, and the default is centre** — Pen's re-save removes
   `"strokeAlignment": "center"` as redundant. With `k` = 0, ½, 1 for inner, centre, outer, each side's band runs from
   `k·w` outside the edge to `(1 − k)·w` inside it; square corners are filled (the ring is outer rectangle minus inner
   rectangle). Pen collapses four equal per-side widths to a uniform `strokeWidth` on save.
7. **Rounded corners.** For a corner of radius `r` (clamped to half the box) between sides of widths `a` (the side the
   x axis crosses) and `b`:
   - inner edge: an ellipse of radii `max(0, r − (1 − k)·a)` × `max(0, r − (1 − k)·b)` — the CSS border rule;
   - outer edge: a **circle** of radius `r + k·min(a, b)`, except that a **centred** stroke whose half-width
     `min(a, b)/2` exceeds `r` gets radius `min(a, b)/2`. Pen's *uniform* centred strokes do the same (radius 6, width
     16 → outer radius 8, not 14), so this is its stroker, not a per-side quirk; outer alignment never takes that branch
     (radius 6, width 8 → 14).
   Measured by the gap between the box corner and the first covered pixel on the edge row, converted to a radius, on
   24 probe boards (radii 6 and 12 × widths 2–24 × centre/outer); the model then reproduces every per-side board to a
   coverage MAE ≤ 0.04 (0.1 of 255) with no pixel off by more than half its coverage.
8. **Per-side widths on an ellipse are not bands.** Pen draws an ellipse carrying per-side widths `4/16/24/8` as a
   thin uniform stroke, for every alignment. Not modelled: Woodcase keeps its old fallback (inner bands clipped to the
   shape) for ellipses, paths and polygons, and says so in its docs. Filed as a follow-up below.

## What changed in Woodcase

- `PenFill.PenGradientFill.frameTransform(in:)` (`Rendering/PenFill+GradientFrame.swift`) is finding 1 as a
  `CGAffineTransform`. `PenFillRenderer` concatenates it and draws linear and radial gradients in gradient space;
  angular gradients are still a per-pixel bitmap, now computed at the context's **device** resolution (it was one
  bitmap pixel per point, upscaled at 2x) and taken back through the inverse frame, with stops padded.
- `PenStrokeRenderer+PerSide.swift` builds the per-side ring (findings 6–7) for frames, rectangles and browser nodes;
  `PenRenderer` and `PenBrowserPlaceholder` pass the node's box and corner radii. The old doc comment claiming per-side
  strokes are "always inner … matching CSS/Pen border behavior" was **wrong** and is gone.

## Fixtures and figures

`scripts/gen-paint-geometry-fixtures` writes both fixtures; `scripts/pen-oracle <fixture> --scale 1,2` (gradients) and
`--scale 2` (strokes) wrote the committed references. Tests: `PenGradientGeometrySnapshotTests` (MAE < 1 per artboard at
1x and 2x), `PenGradientFrameTests` (the transform), `PenPerSideStrokeAlignmentTests` (every band edge on 19 rows × 18
columns within 0.5 pt of Pen's at 2x, plus MAE < 1). Figures from `swift test --filter
"PenGradientGeometrySnapshotTests|PenPerSideStrokeAlignmentTests|PenSnapshotTests"`, each test printing its MAE, on
`main` at `fa9b1d7` (before) and this change (after):

| Case (MAE) | Before 1x / 2x | After 1x / 2x |
|---|---|---|
| linear, rotation 0 or 90, any box | 0.11–0.24 | unchanged |
| linear, rotation 45/135/210, square | 4.3–4.5 | 0.09–0.15 |
| linear, rotated, wide or tall | 5.0–9.2 | 0.09–0.14 |
| linear, centre + size (`lin-wide-r315-centre-size`, the fills report's twin) | 10.80 / 10.80 | 0.12 / 0.08 |
| angular, square, any rotation | 0.14 / 0.22 | 0.07 / 0.07 |
| angular, wide or tall | 9.0–12.3 | 0.07 |
| angular, stops 0.2–0.8 | 6.11 / 6.13 | 0.03 / 0.03 |
| radial, rotation + non-uniform size | 6.4–15.3 | 0.09–0.44 |
| per-side, inner, square corners | 0.00 | 0.00 |
| per-side, inner, rounded | 0.27–0.38 | 0.01–0.02 |
| per-side, centre / unset | 4.8–20.3 | ≤ 0.02 |
| per-side, outer | 9.6–42.2 | ≤ 0.03 |

Existing fixtures (2x): `render-gradients` 0.669 → 0.133 and `render-clipping-and-gradients` 0.622 → 0.060 — both
contain 45° linear gradients (a square rect, an ellipse, an off-centre rect) that the old code stretched to cover the
box's diagonal; `gradient-extras`, `render-strokes-and-paths`, `render-shapes-and-fills` and the transform and blur
fixtures are unchanged to the last digit. None contains a per-side stroke.

## For RapidPro

RapidPro converts `PenFill` and `PenStrokable` itself and evaluates paints in its shaders, so it needs the same two
changes (not made here; read-only):

- `Conversion/PenFill+RenderFill.swift` + `Shaders/Common.h` `evaluateFill`: pass the frame (the inverse of
  `scale(size) → rotate(−rotation)`, a 2×2, plus `center`) instead of a direction vector, and evaluate in gradient space
  `q = M · (uv − center)`: linear `t = ½ − q.y`, radial `t = 2|q|`, angular `t = (atan2(q.y, q.x) + π/2) / 2π`.
  Today its linear gradient is already in UV space but ignores `center` and `size`; radial ignores `size` and
  `rotation` (fixed radius ½); angular ignores `rotation` and `size`. Clamp `t` into the stop range (pad) for angular.
- `Metal/RapidProRenderer+InstanceBuilding.swift` `strokeExpansion` and `Shaders/RectShader.metal`
  `perSideStrokeCoverage`: per-side strokes are inside-only there ("matching CG reference" — no longer true). They need
  the alignment offsets of finding 6 and the corner radii of finding 7, and the quad must expand by `k·width` per side.

## Follow-ups

- Per-side widths on ellipses, paths and polygons (finding 8): measure what Pen draws — the probe suggests a uniform
  stroke of the smallest (or top) width — and replace the fallback.
- The React emitter's gradients (`ReactEmitter+Styles.swift`) use a plain CSS angle; CSS `linear-gradient` angles
  are in pixel space, so they will not match Pen on non-square boxes either. Not examined here.

## Reproduce

Probe scripts are throwaway (`fit.py`, `hyp.py`, `model*.py`, `radii*.py` in the session scratchpad); their method:
red→blue ramps so `t = B / 255`, a least-squares plane fit of `t` over the unclamped pixels for linear paints, and
hypothesis tests of `t` per pixel for angular and radial ones; for strokes, a supersampled rasteriser of the ring model
compared with Pen's 2x coverage. The committed fixtures reproduce every figure in the table.
