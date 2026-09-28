# Pencil Rendering Quirks

Differences between Pencil's renderer and standard SVG/CSS behavior, discovered during snapshot test development on 2026-03-23.

## Path Geometry Normalization

**Key finding:** Pencil normalizes SVG path geometry to fill the node's declared `width`/`height`.

When a `.pen` file specifies a `path` node with `width`, `height`, and `geometry`, Pencil does **not** use the SVG path coordinates as-is. Instead, it:

1. Computes the path geometry's bounding box
2. Translates the bounding box origin to `(0, 0)`
3. Scales each axis **independently** (non-uniform) to fill the node's declared dimensions

This is equivalent to SVG's `viewBox` with `preserveAspectRatio="none"`.

### Example

```json
{
  "type": "path",
  "width": 200,
  "height": 200,
  "geometry": "M 10 10 L 50 10 L 50 50 L 10 50 Z"
}
```

The geometry defines a 40x40 square at offset (10, 10). Pencil renders this as a 200x200 square filling the entire node — the path is translated to the origin and scaled 5x in both axes.

### Edge Cases

- **Zero-height paths** (e.g., horizontal lines): Only the x-axis is scaled; the y-coordinate is translated to the node's top edge.
- **Zero-width paths** (e.g., vertical lines): Only the y-axis is scaled.
- **Stroke thickness is not scaled** — only the path geometry is transformed; stroke width remains at the declared pixel value.

### Woodcase Implementation

Implemented in `PenShapeBuilder.svgPath()`. The `rect` parameter (previously ignored) is now used to compute the normalization transform via `CGPath.copy(using:)`.

## Stroked Path Positioning (Bitmap Alignment Theory)

When a path has a thick stroke, Pencil and Woodcase produce slightly different positioning. Both normalize the geometry and allow stroke overflow, but they differ in what is aligned to the box:

- **Woodcase:** Aligns the path geometry to the box. Stroke overflows symmetrically.
- **Pencil:** Appears to rasterize the path+stroke into a bitmap, then align the bitmap's top-left to the box position. The stroke extends the bitmap, so the path content shifts down-right by ~`stroke_width/2`.

The offset depends on the stroke's actual rendered extent, not just its thickness. For a simple thick stroke it's roughly `stroke_width/2`, but miter joins on sharp angles can extend much further. Woodcase does not replicate this offset — it appears to be an artifact of Pencil's rasterization pipeline. This is the primary contributor to the higher MAE (~5) on stroke-heavy fixtures.

## Dash Pattern Limitation

The `.pen` format schema includes `dashPattern` on strokes:

```json
"stroke": { "dashPattern": [10, 5] }
```

However, the Pencil MCP silently drops the `dashPattern` property when creating or updating nodes. Woodcase's `PenStrokeRenderer` supports dash patterns via `CGContext.setLineDash`, but fixtures created through the MCP will not include them. Dash patterns may need to be added manually to `.pen` fixture files for testing.

## Remaining MAE Differences

Even with path normalization, some rendering differences remain between Pencil and Woodcase (typically MAE ~5 for stroke-heavy fixtures). The primary cause is the stroked path positioning offset described above. Secondary contributors:

- Anti-aliasing algorithm differences between Pencil's renderer and CoreGraphics
- Miter limit handling at sharp join angles
- Sub-pixel rounding differences in stroke alignment
