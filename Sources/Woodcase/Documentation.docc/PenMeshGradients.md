# Mesh Gradients

How Woodcase turns a `mesh_gradient` fill into triangles and pixels, without CoreGraphics.

## Overview

A mesh gradient is a `columns × rows` grid of colored vertices joined by Bézier
patches (``PenFill/PenMeshGradientFill``, ``PenMeshPoint``). The mesh core in
`Sources/Woodcase/Rendering/Mesh/` is pure Swift and Foundation, so it builds on Linux,
and it has three stages that each return plain data:

```swift
let grid = try PenMeshGrid(fill)                        // validate and resolve
let mesh = PenMeshTessellator().tessellate(grid, width: 400, height: 400)
let raster = PenMeshRasterizer.rasterize(mesh, width: 400, height: 400)
```

Or in one call: `PenMeshRasterizer.rasterize(grid, width: 400, height: 400)`.

- ``PenMeshGrid`` applies Pen's rules for whether a fill is drawn at all. A missing
  `columns`, `rows`, `points` or `colors`, or a count that is not `columns × rows`, is a
  ``PenMeshGrid/Invalidity`` and the fill paints nothing. Omitted handles take the grid's
  defaults. A color string is read as Pen's mesh reads it (see "Colors" below), and a
  color that is still a variable becomes opaque black: resolve variables first with
  ``PenVariableResolver``. A malformed point is placed as
  Pen places it, or makes the fill paint nothing; see "Malformed points" below.
- ``PenMeshTessellation`` is a vertex buffer: positions in device pixels, one
  unpremultiplied color per vertex, and triangle indices. A GPU renderer can upload it
  unchanged and draw it with Gouraud shading.
- ``PenMeshRaster`` is premultiplied RGBA8 in sRGB, ready to wrap in a `CGImage` or
  encode as a PNG with ``PenMeshRaster/pngData()``, which uses ``PortablePNGEncoder``
  and so stays free of CoreGraphics too. The React emitter bakes meshes this way (see
  <doc:PenCodeGen>).

The fill's `opacity`, blend mode and clip to the node's path are the caller's: the core
paints the node's whole box (`width × height`, not the path's bounding box).
``PenRenderer`` is one such caller: it rasterizes at the context's device scale (at
least 2x in a PDF, as Pen's own PDF export does), wraps the raster as a `CGImage`, and
draws it over the node's box through the fill's clip.

## Colors

Pen's mesh does not read its colors by ``PenHexColor``'s grammar, and neither does
``PenMeshColor/init(penMesh:)``. Pen drops one leading `#`, then goes by how many UTF-16
code units are left:

- **3**: each digit doubled, one channel each, opaque; a digit that is not hex reads
  0, so `red` is `#00EEDD`.
- **6** or **8**: the whole string is one JavaScript `parseInt(digits, 16)`, which skips
  leading whitespace, a sign and `0x`, reads the longest run of hex digits after them,
  and gives `NaN` — read as 0 — for none. The number's low 32 bits split into bytes,
  `RRGGBB` opaque or `RRGGBBAA`. So `#GGGGGG` is opaque black, `#eGeGeG` is
  `#00000E`, `#-f-f-f` is `#FFFFF1` and `#GGGGGGGG` is transparent.
- **Any other length** — 4-digit `#RGBA`, `#FF000`, `""`, `##F00` — is transparent
  black: that vertex paints nothing, and blends toward nothing.

Measured 2026-09-27 against Pen's exports of `render-mesh-colors.pen`, one 2×2 mesh of
one color string per frame over a `#00FF00` fill (`scripts/pen-oracle
Tests/WoodcaseTests/Fixtures/render-mesh-colors.pen --scale 1 --accept-invalid
--no-layout`, `pen` CLI 0.3.9); `PenMeshColorSnapshotTests` pins every frame and
`PenMeshColorTests` every row. The SwiftUI emitter writes the same colors
(``PenMeshColor/hexColor(penMesh:)``), and `woodcase lint`'s `mesh-gradient-distorted`
names every color Pen reads as nothing or as another color.

> Correction, 2026-09-27: this page said a color Pen cannot read becomes opaque black.
> That was wrong for every malformed color but a six-digit one with no hex prefix;
> most read as transparent.

## Malformed points

A file can write a vertex in neither wire form: `"oops"`, `[1]`, an object whose
`position` is a string. Pen opens such a file, so Woodcase does too. A file decode keeps
the value verbatim as ``PenMeshPoint/malformed(_:)`` and writes it back unchanged;
authoring input (``PenDecodingMode/authoring``, an agent's `set` or `add`) refuses it.

Pen never says what it does with one; its exports and re-saves do (headless `pen` CLI
0.3.9, `render-mesh-malformed-points.pen`, measured in
`project/2026-09-26-what-pen-drops-from-a-file.md`).
``PenMeshPoint/placement(gridPosition:defaults:)`` follows it:

| Written | Pen draws |
|---|---|
| `"oops"`, `null`, `42`, `true` | the vertex at its grid position (``PenMeshPoint/gridPosition(column:row:columns:rows:)``), default handles |
| an object with no `position`, or `"position": null` | the grid position, with the handles it names |
| `[0.3, 0.2, 9]`, or a longer `position` or handle | the first two numbers |
| `[0.3, null]`, `[true, false]` | `null` as 0, a boolean as 0 or 1 |
| `[1]`, `[]`, `["0.3", "0.2"]`, `[[0.3], [0.2]]` | nothing for the **whole fill** |
| `"position": "oops"`, a handle `[1]`, `"oops"` or `{}` | nothing for the whole fill |

``PenMeshGrid`` builds each vertex from its placement and throws
``PenMeshGrid/Invalidity/unplaceablePoint(index:)`` for the last two rows, so every
consumer of the grid — ``PenRenderer``, the React emitter's baked PNG, RapidPro — draws
what Pen draws. The lint reports both kinds (<doc:WoodcaseLint>).

## What a patch is

Each patch is a bicubic tensor-product Bézier surface. Its 4×4 control net comes from the
corner positions and handles, with the four interior points on the zero-twist
(parallelogram) rule; see ``PenMeshPatch``. Its color is a bilinear blend of the four
corner colors at *smoothstep-eased* parameters, `t²(3 − 2t)`, on unpremultiplied
sRGB-encoded channels. The color follows the parameters, not the position, and the
default handles are a quarter of a cell, not a third. Both rules match Pen's exports,
measured in `project/2026-09-26-mesh-gradients.md`.

Where the mesh leaves part of the box uncovered, the raster is transparent. Where it
folds over itself, later patches paint over earlier ones, in row-major order.

## Adaptive subdivision

Pen cuts every patch into a fixed 32 × 32 cells whatever its size on screen, so its
large meshes show faceting. Woodcase deliberately differs: ``PenMeshTessellator``
chooses each patch's cell counts from an error bound, so the facets stay below what the
output can show at any size. That is a small, accepted difference from Pen's pixels
(the 2026-09-26 ruling on leaf `OHdROl`).

The bound is the standard one for piecewise-linear interpolation over a triangulated
grid: `error ≤ ⅛ (Mᵤᵤ hᵤ² + 2 Mᵤᵥ hᵤ hᵥ + Mᵥᵥ hᵥ²)`, where the `M`s bound the second
derivatives over the patch and `h` is the cell size in parameter space. Two quantities
are held to it:

| Quantity | Tolerance | Why |
|---|---|---|
| Position, in device pixels | ¼ px (``PenMeshTessellator/geometricTolerance``) | Below what sampling at pixel centers can show |
| Premultiplied color | ½ of an 8-bit step (``PenMeshTessellator/colorTolerance``) | The interpolated color rounds to the exact color's step or its neighbor |

The geometric term comes from the control net's second differences scaled to pixels, so
its cell count grows with the square root of the patch's size on screen. The color term
does not depend on size, and never asks for more than about 60 cells. A flat,
single-color patch gets one cell. Every patch in a column shares that column's largest
count, and every patch in a row shares that row's, so the whole mesh is one lattice with
no T-junctions.

## No seams

``PenMeshRasterizer`` snaps positions to 1/256 px and evaluates edge functions in exact
integer arithmetic, with the top-left fill rule. A pixel center on an edge two triangles
share is therefore covered by exactly one of them. For a translucent mesh this means no
doubled pixels (darker lines) and no missing ones (cracks) along patch or cell edges;
`PenMeshSeamTests` holds the rasterizer to that.

Color is computed in `Double` and rounded once, when it is written. Pen quantizes the
blended vertex colors to 8 bits first, by truncation; skipping that step is worth at
most one 8-bit step. This is a deliberate difference, not a gap to close (ruling, Ben,
2026-09-26: where Woodcase is more correct than Pen, keep it and accept the small error).
It is most of the 0.23–0.38 mean absolute error the Pen-reference tests allow on opaque
meshes: about half the samples land one step brighter than Pen's.

## Topics

### Model

- ``PenMeshGrid``
- ``PenMeshPatch``
- ``PenMeshColor``

### Output

- ``PenMeshTessellator``
- ``PenMeshTessellation``
- ``PenMeshRasterizer``
- ``PenMeshRaster``
- ``PortablePNGEncoder``
