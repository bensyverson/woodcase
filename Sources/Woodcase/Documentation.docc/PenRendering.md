# Rendering .pen Documents

An overview of how the renderer turns a laid-out document into pixels.

## Overview

``PenRenderer`` is the final stage of the Woodcase pipeline. It takes a ``PenDocument`` and a dictionary of layout rectangles (from ``PenLayoutEngine``) and produces a `CGImage`.

```swift
let penFileDir = penFileURL.deletingLastPathComponent()
let image = PenRenderer.render(
    document,
    layoutRects: rects,
    size: CGSize(width: 800, height: 600),
    scale: 2,
    imageProvider: PenRenderer.imageProvider(relativeTo: penFileDir)
)
```

The renderer walks the document tree depth-first, drawing each node at its computed position. It supports shapes, fills, gradients, text, strokes, transforms, effects, and compositing.

## Architecture

The renderer is composed of several internal helper types, each responsible for a specific concern:

| Helper | Responsibility |
|--------|---------------|
| `PenShapeBuilder` | Draws the outline `PenShapeGeometry` computes for each node (rectangles, ellipses, polygons, lines, SVG paths) as a `CGPath` — see *Shape Geometry* |
| `PenFillRenderer` | Renders solid, gradient and image fills through a clip (a path and its fill rule) over a paint domain (the node's box) |
| `PenStrokeRenderer` | Renders a ``PenStrokable`` node's stroke — paint, width, alignment, linecap and linejoin |
| `PenTextRenderer` | Renders text via Core Text — a lone solid color directly, any other paint through the glyph outlines |
| `PenIconFontRenderer` | Renders icon font glyphs via Core Text single-glyph drawing, painted as text is |
| `PenTransformBuilder` | Builds `CGAffineTransform` from rotation and flip properties |
| `PenEffectRenderer` | Renders outer shadows, inner shadows, layer blur and background blur |
| `PenShadowSilhouette` | The opaque shape an outer shadow is cast by |
| `PenGaussianBlur` | The CPU Gaussian both blurs use, on encoded sRGB values |

These helpers are `internal` — only ``PenRenderer``, ``PenColorParser``, ``PenHexColor``, ``PenSVGPathParser`` (with ``PenPath``, ``PenPathCommand`` and ``PenPoint``), ``PenBrowserPlaceholder/Style``, and the ``PenBlendMode`` extension are public API.

``PenHexColor`` is the format's one hex color grammar (`#RGB`, `#RRGGBB`, `#RRGGBBAA`, the `#` optional; `#RGBA` and signed numbers refused). It needs only Foundation, and ``PenColorParser`` wraps its result into a `CGColor`. The mesh core does not use it: Pen's mesh reads its color strings its own way (``PenMeshColor/init(penMesh:)``, <doc:PenMeshGradients>).

## Shape Geometry

A node's outline is decided once, without CoreGraphics, and drawn by a thin CoreGraphics
layer. `Sources/Woodcase/Geometry/` is pure Swift and Foundation, so the code emitters
read the same outline the renderer draws, and it builds on Linux.

- ``PenPath`` is the parse of a `path` node's SVG `geometry`: a list of
  ``PenPathCommand``s — move, line, quadratic, cubic, close — fully resolved. Relative
  commands are absolute, `H`/`V` are lines, the reflected control point of `S`/`T` is
  written out, and every elliptical arc is converted to cubics (at most 90° each, per
  the SVG implementation notes). ``PenPath/mapped(onto:viewBox:)`` maps it onto the node's
  box, through its viewBox or by stretching its ``PenPath/tightBounds``.
- `PenShapeGeometry` computes every shape's `PenShapeOutline`: rectangles (plain, uniformly
  rounded, or per-corner with tangent arcs), ellipses, rings, pie slices and arc donuts,
  polygons (sharp or rounded), lines and mapped paths, and the fill rule each is filled with.
  Beyond the path commands an outline uses only primitives that CoreGraphics and SwiftUI's
  `Path` both provide under the same name — `addArc(tangent1End:tangent2End:radius:)`,
  a unit-circle `addArc(center:radius:startAngle:endAngle:clockwise:transform:)` scaled onto
  the ellipse, `addRect`, `addRoundedRect` and `addEllipse` — so each element maps
  one-to-one onto either. `PenShapeOutline.svgPathData(number:)` writes the same outline as
  SVG path data — an elliptical arc as an SVG `A` between its end points, a tangent arc as
  its lead-in line and circular arc — which is how the React emitter draws an arc or a ring.
- `PenShapeBuilder` and ``PenSVGPathParser`` are the CoreGraphics side: they build a
  `CGPath` from the outline, element for element, and nothing more.

The parser is lenient where Pen is: whitespace and commas separate, a sign or a second
decimal point starts a new number, an unknown non-letter character is skipped, and an
arc flag may be written without a separator (`a5 5 0 0110 0`). It rejects data that
starts with a number, names a command SVG does not define, or runs out of arguments.

## Render Order

For each node, the renderer follows this sequence:

1. **Skip** if the node is disabled or non-visual
2. **Translate** the context to the node's position
3. **Transform** — apply rotation and flip around the center of the node's unturned box, centered in its layout rect (a `group`'s box is its children's union, and the context then moves to the group's anchor — see *Transforms*)
4. **Opacity** — begin a transparency layer if opacity < 1
5. **Blend mode** — set the node's blend mode
6. **Background blur** — capture the backdrop under the node, blur it, and draw it back clipped to the node's shape
7. **Own content, in Pen's paint order** — outer shadows, then fills (or text, icon glyphs), then inner shadows, then the stroke; a layer blur wraps this and the children when present
8. **Children** — inside the frame's clip, when it clips; a frame's clip never cuts its own shadow or stroke
9. **Restore** — end transparency layer and restore graphics state

## Coordinate System

The .pen format uses a top-left origin (y increases downward), while CoreGraphics uses a bottom-left origin (y increases upward). The renderer flips the coordinate system once at context creation:

```
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)
```

All subsequent drawing uses top-left coordinates. Core Text requires a local re-flip since it draws in native CG coordinates.

### Which rect frames a render

A node has three extents (<doc:PenEngine>, *Three extents*), and a renderer reads two of
them. It draws each node through its placement (``PenPlacement``: the box and the map
into its parent, which `PenRenderer.enter` applies to the context), never through its
layout rect directly. And it frames a render on one of two rects: the layout rect
(``PenRect``), which the sizing entry point
``PenRenderer/render(_:layoutRects:size:scale:colorSpace:rootNodeID:overrides:imageProvider:)``
draws a subtree at, so an outer stroke, a shadow or an overhanging child is cut off at
its edge; or the painted extent (``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``),
which is what Pen frames an export on. To render the painted extent, position a context
at that rect's origin and size and draw through the context entry point,
``PenRenderer/render(_:layoutRects:into:rootNodeID:overrides:imageProvider:)``, as
`woodcase shot --extent painted` does; to match Pen's export pixel for pixel, grow it to
whole pixels at the scale first (``PenRect/grownToWholePixels(at:)``). A viewport culler
or a dirty-rect pass wants the painted extent in canvas coordinates,
``PenLayoutEngine/canvasPaintedExtent(of:in:layoutRects:)``.

The context entry point draws in canvas coordinates, so a PDF page must be moved to the
frame's origin before it draws, or a frame anywhere but (0, 0) lands off its page and the
page comes out blank. ``PDFExporter/Page/init(frame:of:layoutRects:imageProvider:)`` is
that page, sized to the frame and positioned on it; `woodcase render --format pdf` and the
viewer's PDF export both build their pages with it.

## Supported Features

### Shapes
Rectangles (with per-corner radii), ellipses (with optional inner radius for donuts, and a start and sweep angle for arcs), regular polygons, lines, and arbitrary SVG paths. A path node's geometry is mapped onto its box either by stretching the geometry's tight bounding box to fill it (the default) or, when the node declares a ``PenViewBox``, by stretching that region onto the box — non-uniformly, with overflowing geometry drawn unclipped. See <doc:PenInteroperability> for the details.

An ellipse's angles are counter-clockwise from the right and *parametric*: the angle on the unit circle before it is stretched to the box, so on a wide ellipse a 30° cut does not run at 30° on screen. An arc with no `innerRadius` is a pie slice closed through the center. An arc *with* one is a single closed ring, as Pen draws it: the outer arc over the sweep, a straight cut along the end angle to the inner ellipse, the inner arc back over the same sweep, and a straight cut home — the inner ellipse is never drawn outside the sweep. `PenArcDonutTests` pins this against Pen's renders of `Fixtures/render-arc-donut.pen`.

### Fills
Solid colors, gradients (linear, radial, angular), mesh gradients, and image fills. Multiple fills layer bottom-to-top. Each fill can be independently enabled/disabled and have its own blend mode. Image fills are placed by their `mode` and cropped by their `transform` (format 2.20) through ``PenImagePlacement``, the one placement every renderer and emitter shares: `stretch` lays the crop box over the whole box, `cover` and `contain` give it the cropped image's aspect and scale it to cover or fit the box, centered, and the image is drawn through the crop into it. A missing mode is `cover` (an older file's paint is given an explicit `stretch` when it is read, so it draws as it did). Only `contain` clips to its crop box; `cover` first keeps its crop window inside the image, so it never shows past the image's edge, while `stretch` and `contain` show nothing there. `PenImageCropSnapshotTests` pins all 48 boards of `render-image-crops.pen` — every mode on a wide and a tall box with no crop, the right half, a centered zoom, a window past the edge, one larger than the image, a shear and a quarter turn, plus an ellipse, an outer stroke and half opacity — against Pen 1.2.15's exports at MAE 0.002–0.076 (`swift test --filter PenImageCropSnapshotTests`, 2026-10-03; 1.9–23.8 on the cropped boards before). Images are provided via a caller-supplied ``PenRenderer/ImageProvider`` callback. For `.pen` files on disk, use ``PenRenderer/imageProvider(relativeTo:remote:)``: it resolves relative URLs against the file's parent directory and serves `http(s)` URLs from the cache ``RemoteImageResolver`` fills — see <doc:PenRemoteImages>. ``PenRenderer/fileImageProvider(relativeTo:)`` is the local-only half. A mesh gradient (``PenFill/PenMeshGradientFill``) is rasterized by the mesh core (<doc:PenMeshGradients>) at the context's device scale — at least 2x in a PDF, which therefore carries it as an image — and drawn over the node's box through its outline, with the fill's own opacity and blend mode. A mesh Pen would not draw (a missing field, or a count that is not `columns × rows`) draws nothing. A shader fill (``PenFill/PenShaderFill``) is preserved in the model but **never executed** — no GLSL runtime — so the renderer treats it as fully transparent. That is a gap, not a match: Pen runs the shader in its exporter — uniforms, `sampler2D` images, `@sdf`, `@backdrop`, `@time` as 0, on shapes, text and icons (`render-shader-fills.pen`, where CG scores MAE 11.7–159 per board with `shot` + `png-mae`; finding F1 of `project/2026-09-27-fidelity-gaps.md`). So Woodcase says so wherever it leaves one out: ``ShaderFills/diagnostic(under:)`` is one warning naming every node with an enabled shader, which `woodcase render` prints once per document and `woodcase shot` once for the node it draws; `woodcase lint` reports each shader (`shader-not-drawn`), and both code generators warn per node (<doc:PenCodeGen>).

A gradient is laid out in the node's *normalized* box, exactly as Pen lays it out: `center` and `size` are fractions of the box, and `rotation` turns the gradient counter-clockwise inside that unit square before the square is stretched to the box. So on a box that is not square a 45° linear gradient does not run at 45° on screen, and radial and angular gradients become ellipses; `size` scales the gradient's own axes before the rotation. A linear gradient runs bottom to top at rotation 0 and its `size.height` is its length; an angular gradient starts pointing up and sweeps clockwise; stops that do not reach 0 or 1 pad with the end colors. The findings are in `project/2026-09-26-gradient-geometry-and-per-side-strokes.md`. `PenFill.PenGradientFill.frameTransform(in:)` is that same map — Pen's one computation of a gradient's scale, rotation and center (``GradientGeometry/affineComponents``, in `CodeGen/Paint/`, shared with the code emitters) plus the final stretch to the node's box; it is not reimplemented in CoreGraphics terms.

A fill is drawn through two separate inputs. The **clip** — the node's outline and its fill rule — is where the fill shows; the **domain** — the node's layout box — is where the paint is laid out: where a gradient's stops land and where an image is stretched, filled or fitted. Pen lays every paint over the box whatever the outline inside it, so a hexagon, a triangle, a quarter-pie arc, a curve whose control points overshoot its box, or a `viewBox` path drawn inside its box all show the slice of the paint the whole box would show. Outlines with holes — an ellipse with an `innerRadius`, a path with `fillRule: evenodd` — are clipped with the even-odd rule, so every fill type, not only solid colors, draws through the ring and leaves the hole empty. Each fill is clipped on its own, so stacked, translucent and blended fills composite through the outline one at a time. `PenFillRenderer.renderFills(_:clip:fillRule:domain:in:imageProvider:)` is the one entry point; it also carries glyph outlines (text and icon paints, see *Text*) and stroke outlines (see Strokes below), with the node's box as the domain in every case. `PenFillDomainTests` pins it against Pen's renders; the findings are in `project/2026-09-26-fill-clip-and-domain.md`.

### Strokes
Uniform strokes honor `strokeAlignment` (inner, center — the default — or outer), width, linecap and linejoin. A per-side `strokeWidth` on a frame, rectangle or browser node draws a band per side that honors `strokeAlignment` too: each band runs from `k·width` outside the edge to `(1 − k)·width` inside it, `k` being 0, ½ or 1 for inner, center and outer. Rounded corners follow Pen: the inner edge's corners are ellipses of radius `max(0, r − (1 − k)·width)` along each axis, and the outer edge's are circles of radius `r + k·m`, `m` the narrower adjacent width — except that when a centered stroke's half-width `m / 2` exceeds `r`, the outer corner's radius is `m / 2`. A per-side width on any other shape — an ellipse, a polygon, a path, a line — Pen draws as **one uniform stroke of the `top` width**, the other three sides ignored, and with no `top` it draws no stroke; `strokeAlignment`, the join and the cap apply as they do to any uniform stroke. `render-per-side-shapes.pen` pins it (`scripts/pen-oracle … --scale 2`, Pen 1.2.14): widths t12 r2 b6 l0 put an ellipse's ring 6 pt outside its box on every side, t2 r10 b4 l6 put it 1 pt outside, the inner and outer boards place the 12 pt ring wholly inside and outside the outline, an ellipse with no `top` draws nothing, and a line draws a 12 pt stroke; `PenPerSideShapesTests` holds all fourteen boards within MAE 0.5 (0.00–0.17). Pen's choice of `top` looks arbitrary and could change, which is why the fixture pins it; the rule lives in one place, ``PenStrokable/drawn(on:)``, which the renderer, the shadow silhouette and both code emitters call, and `woodcase lint` warns about such a width (`per-side-stroke-on-shape`, <doc:WoodcaseLint>). Until 2026-09-27 the renderer drew these widths as bands along the box clipped to the shape (MAE 14.5–15.6 against Pen on the `-top12` boards).

A stroke takes every paint a fill does — gradients, images, stacks, fill opacity and blend modes — through the same clip/domain seam: the stroke's **outline** is the clip and the node's **box** is the domain, for every alignment. The outline of a uniform stroke is the stroked path (`copy(strokingWithWidth:)`, twice the width for inner and outer strokes, cut to the shape or its complement); a per-side stroke's outline is its ring. So a gradient's stops sit on the node's edges and pad beyond them, and an image is placed over the box and draws nothing outside the placed image — an outer stroke painted with an uncropped `stretch` or `contain` image is invisible, and a `cover` image shows only where it overhangs the box, exactly as in Pen. A cropped `cover` or `stretch` image is not cut at its crop box either, so an outer stroke shows the image beyond the crop (`render-image-crops.pen`, board `cover-stroke-zoom`). A mesh stroke is the mesh core's raster through the same seam; no Pen reference pins it yet. A stroke that is one solid color with no blend mode is still drawn with `strokePath()`, pixel for pixel as before. `PenStrokeFillTests` pins it against Pen's renders; the findings are in `project/2026-09-26-stroke-paints.md`.

### Script Nodes
A `script` node (``PenNode/ScriptData``) is a sized placeholder for a user-authored JavaScript file — Woodcase never runs it. The node still participates in layout like any other leaf, occupying the space its `width`/`height` declare, but the renderer draws nothing for it.

### Browser Nodes
A `browser` node (``PenNode/BrowserData``, new in Pen 2.19) embeds a live web page, and Pen draws a snapshot of it. Woodcase **never loads the page**: a render must not depend on the network, and no offline renderer could match a live snapshot anyway. The node lays out like a rectangle — its `width`/`height`, `fill_container` and `fit_content` behave exactly as a rectangle's do — and the renderer draws a quiet placeholder in its place:

- a light neutral fill (`#F4F4F5`), which is what casts the node's outer shadow;
- a 1pt `#D4D4D8` border inside the edge — replaced by the node's own stroke when it declares one;
- the URL as stored (Pen writes `https://example.com` as `example.com`), or `browser` when it has none, as an 11pt `#A1A1AA` label centered in the node and truncated with an ellipsis 12pt from each side.

All of it is clipped to the node's corner radius. The node's effects are drawn as on any other shape. A browser takes no fill in the format, so the placeholder fill is always drawn. These values are one public value, ``PenBrowserPlaceholder/Style/standard``, with the URL-or-`browser` rule as ``PenBrowserPlaceholder/Style/label(for:)``: a renderer that draws browsers itself (RapidPro does) reads them from there rather than keeping a copy. `PenBrowserRenderTests` pins the look with pixel probes and against `Fixtures/browser.png`, a reference Woodcase itself rendered — there is no Pen reference to hold it against.

### Connections

A `connection` (``PenNode/ConnectionData``) is drawn as a straight segment from its source's anchor to its target's — the center of a node's box, or the middle of one of its edges — painted by the connection's own stroke exactly as a `line` is: every paint a stroke takes, its width, cap and join, and the connection's opacity. With no stroke paint it draws nothing, as a line does. Its `x`, `y`, rotation and flips play no part; a connector is where its endpoints are. The endpoints are found in canvas coordinates, composed once per render by ``PenLayoutEngine/canvasRects(in:layoutRects:)``, so an endpoint nested in a frame, or inside a component instance by its `instance/child` path, is found where it is drawn. A connection whose endpoint names no node draws nothing.

There is no Pen rendering to match. Pen 1.2.14's validator accepts a connection, but neither Pen's desktop app nor its headless engine loads one: both drop the node when they open the file. `PenConnectionRenderTests` pins Woodcase's drawing with pixel probes, and RapidPro draws the same segment. The React emitter writes nothing for a connection: Pen allows one only between artboards at the top level, where no component or page markup reaches.

### Text
Text content is a string or a `$variable`; font, color and decorations are node-level properties. Horizontal alignment (left, center, right, justify) and vertical alignment (top, middle, bottom). Styled runs were removed from the format in 2.17 — a legacy document's runs are flattened into one string by ``PenRichTextMigrationRule``.

**Lines are placed as Pen places them.** Core Text breaks the text into lines and aligns each horizontally; ``PenTextLines`` then puts every line one pitch below the last (the pitch layout measures, ``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)``), its first baseline at ``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``. Under an explicit `lineHeight` Pen follows CSS: the difference between the pitch and the font's ascent plus descent is split equally above and below the glyphs (half-leading), negative when lines are tighter than the font, and the baseline lands on a whole point. A natural line keeps its baseline at the rounded ascent. Core Text's own placement under a fixed line height put the whole difference on one side, so tight lines sat up to 1.5 pt high. The lines are laid out in a path taller than any text, so a line that overflows a fixed-height box is still drawn, as Pen draws it, and a box is typeset once per draw. `PenTextLineHeightTests` pins the placement against Pen's exports of `render-text-line-height.pen` and `text-line-height-rounding.pen`, line by line. ``PenTextLines`` is public so that another renderer places its lines by the same rule rather than a copy of it: ``PenTextLines/init(_:width:font:fontSize:lineHeight:)`` takes the styled string, the wrapping width, the resolved font and the node's `lineHeight`, and ``PenTextLines/placed(inBoxOfHeight:)`` hands back each line with its baseline origin. RapidPro's `TextRasterizer` draws through it.

**A text node takes every paint a shape takes.** Pen paints text with gradients, images and stacks of fills, each laid over the text node's *box* — not the glyphs' ink, not each line — and shown only where the glyphs are: a vertical ramp runs once down a whole paragraph, and every line of ragged text shares one horizontal ramp. Woodcase draws text two ways from one Core Text layout:

- **No enabled paint** — no `fill`, an empty list, or only disabled fills — draws nothing, text and icons alike, as Pen draws them. A solid whose color does not parse (an invalid hex, an unresolved `$variable`) is still an enabled paint and draws black, as Pen's does; a fully transparent solid draws nothing because it is transparent. `PenUnfilledTextPaintTests` pins every shape against Pen's exports of `render-text-unfilled.pen`.
- **A lone solid color** goes to Core Text, which draws each placed line (`CTLineDraw`).
- **Anything else** — a gradient, an image, two or more fills, a solid with a blend mode — is drawn through the union of the glyph outlines (``PenGlyphOutlines``, built from the same placed lines, flipped into the node's y-down space) with `PenFillRenderer`, the node's box as the domain. Each fill is clipped on its own, so stacks, opacity and blend modes composite through the glyph coverage one at a time, as on a shape. Underline and strikethrough bars are unioned into the outline and take the paint too. Glyphs from a color font (emoji) have no outline; they are drawn by Core Text in their own colors.

Which of the three a node's fills take is ``PenGlyphPaint``, public with ``PenGlyphOutlines`` so that another renderer follows the same rule and paints through the same outlines rather than copies of them: `PenGlyphPaint(fills:)` answers `.nothing`, `.solid` with the color Core Text is handed (black for a solid that does not parse), or `.glyphOutlines`. RapidPro's text rasterizer draws by both, and paints the outlines with its path rasterizer's paint.

The outline route rasterizes the same glyphs slightly lighter than Core Text does, at identical positions, which is why the lone solid keeps Core Text. Because the paint is a clip plus a `CGShading`, a PDF export keeps gradient text as a vector shading. Animation overrides (``NodeOverrides/fills``) paint text and icons as they paint shapes. A mesh fill on text takes the same route: the mesh core's raster, laid over the node's box and shown through the glyphs. A shader fill draws nothing, as on shapes. That is a gap, not a match: Pen runs the shader, on text too (a solid-red shader drew red glyphs and a red icon in Pen, probed 2026-09-27, leaf PRFPX5). No Pen reference pins mesh-on-text yet. `PenTextPaintTests` and `PenTextPaintRouteTests` pin it against Pen's renders in `render-text-fills.pen`; the findings are in `project/2026-09-26-text-and-stroke-fills.md`.

**Resolving a font is a trip out of the process.** ``PenTextMeasurer`` turns a family
name into a `CTFont` through Core Text's font registry, and that registry lives in
`fontd`: `CTFontCreateWithFontDescriptor` sends a *synchronous* XPC message and blocks
the calling thread on the reply, with no timeout. Two consequences shape the code.
``FontResolutionCache`` answers a repeat resolution without going out at all — which is
why it exists, and why it is invalidated wholesale whenever fonts are registered
(``PenFontRegistry``). And every call that does go out passes through
``FontRegistryGate``, one at a time: Swift's cooperative pool has a thread per core, a
blocking call occupies one, and rendering text on every pool thread at once left a whole
process with nothing runnable for five minutes (`project/2026-08-30-suite-stability.md`).

### Icon Fonts
Icon font nodes are rendered as single Unicode glyphs using Core Text. Woodcase bundles six icon font families — Lucide, Feather, Phosphor, and Material Symbols (Outlined, Rounded, Sharp) — which are automatically registered with CoreText on first use via ``PenIconFontRegistry``. Material Symbols variable-weight fonts support the `wght` OpenType variation axis. Users can register additional icon font families via ``PenIconFontRegistry/register(family:fontName:mapping:)``. The glyph is placed as Pen places it, by the font's metrics rather than its ink: its advance centered across the box and its line box centered down it (<doc:PenIconFonts> has the rule and its evidence). An icon's fills paint its glyph exactly as a text node's paint its glyphs, over the icon's box: a gradient on a 120-point icon runs edge to edge of those 120 points, whatever the glyph's ink.

### Effects
Outer shadows, inner shadows, layer blur and background blur; any number of them on one node. Format 2.19 has no shadow spread, and no Pen ever drew one; a file older than 2.19 loses it on the way in, and its inner shadows become outer ones — see <doc:PenEngine>, *Shadows before 2.19*. `PenShadowSnapshotTests` and `PenBlurSnapshotTests` pin all of this against Pen 1.2.14's exports of `render-shadows.pen` and `render-background-blur.pen` at 1x and 2x; the behaviors are unit-tested in `PenShadowFidelityTests` and `PenBackgroundBlurFidelityTests`.

**Shadows.** A shadow's `blur` is twice its Gaussian's sigma, in points. Pen paints a node's outer shadows first, then its fills, then its inner shadows, then its stroke, then its children — so an inner shadow sits *under* the stroke and the children. **Every** shadow in the `effect` array is drawn, in array order, each composited with its own `blendMode`. An outer shadow is cast by the node's **silhouette**, not by its paint: a shape and the part of its stroke outside it, drawn opaque whatever the fill's alpha (a quarter-transparent fill casts a full-strength shadow); a frame casts the shadow of its box, even with no fill, and its children cast nothing of their own; text and icons cast their glyphs'; a line, which has no interior, casts nothing of its own (`render-stroke-shadows.pen`, boards `line-diagonal` and `line-flat`). The shadow never shows *through* the node — it is knocked out under the silhouette, so a translucent fill shows what is behind the node. A group, which has no shape of its own, casts its shadows from the combined silhouette of its descendants, reached through groups only: each descendant counts as it would for its own shadow (a frame by its box, its children not at all), a line contributes nothing, and neither does a child's opacity or its own shadow. A group's inner shadow falls inside that combined silhouette and, unlike a shape's, *over* its children — they are the group's only content (`render-group-shadows.pen`). Inner shadows use the inverted-path technique (clip to the shape, fill the shape's complement with a CoreGraphics shadow); a group's inverted silhouette is drawn rather than built as a path, cast as one layer, and kept only where the silhouette covers. A text's inner shadow falls inside its glyphs, over its fill, the same way: the glyphs are drawn in opaque ink as the silhouette, so a translucent fill, or none at all, still shows the shadow at full strength, as Pen draws it (`render-text-shadows.pen`, pinned at 1x and 2x by `PenTextShadowSnapshotTests`). Before, the renderer drew no inner shadow on text at all. An icon's inner shadow falls inside its glyph the same way (`render-inner-shadow-shapes.pen`, the `icon-*` boards; before leaf `4fZZ38` the renderer drew none). A shape's inner shadow is clipped with the shape's own fill rule, so a ring's hole casts into the ring rather than filling black (`donut`, 19.971 → 0.393). A flat line's stroke paint is laid over the stroke's band, not the zero-height box, which drew nothing (`render-painted-lines.pen`); the editor collapses a ramp across the line there, a kept divergence (<doc:PenInteroperability>).

**Blur.** Layer blur and background blur are Gaussians of sigma `radius / 2` points — `radius · scale / 2` pixels, so a blur looks the same at every render scale — applied to the **encoded** sRGB values, as Pen blurs, not to linear light. Both are CPU convolutions through Accelerate (`PenGaussianBlur`). They used to go through Core Image, which renders through Metal even when asked for its software renderer: wherever no GPU is reachable — the Claude Code Bash sandbox, a headless VM — every blur silently did nothing.

At a 4 px sigma (radius 8 at 1x) Pen's own blur is measurably wider than the Gaussian it names — its export fits sigma 4.24 px — so a blurred edge there differs from Pen's by up to 5/255; at every other sigma measured it is within 3/255. Woodcase keeps the exact Gaussian.

**Background blur** replaces the pixels inside the node's shape with the blurred backdrop: what the canvas already holds under the node, in any ancestor. Only the node's region is captured — its device bounds plus the three sigmas of kernel that reach into it — clamped at the capture's edges. It is drawn clipped to the node's shape, so corner radii, ellipses, paths and ancestor clips hold, and nested background blurs work. A node with **no visible fill** — none, or all disabled, fully transparent or at opacity 0 (``PenFills/hasVisiblePaint``) — shows no blur, as in Pen and Figma; `#FFFFFF01` is enough. It needs a bitmap context: on a PDF there are no pixels to blur, and the node draws without it.

> Known deliberate difference from Pen 1.2.14: Pen draws **no** background blur on a node whose opacity is below 1 (its opacity layer is pushed before the backdrop is read, so the blur reads an empty layer). That is a Pen bug (Ben's ruling, 2026-09-26), and Woodcase does not copy it: a translucent node's background blur is drawn inside its opacity layer like the rest of the node.

### Transforms
Rotation (counter-clockwise degrees) and horizontal/vertical flip, applied around each node's center point.

Pen turns and flips a node about its `x`/`y` anchor, flipping first. The renderer
gets the same picture by turning about the center, because of what the layout rect
holds: the bounds of the turned box, and — for a node placed by its own coordinates
(a root, a child of a `layout: "none"` frame or a group, an absolute child) — at the
place the anchor turn puts them (<doc:PenEngine>, *Absolute containers and
`fit_content`*). `PenRenderer.enter` draws the node's unturned box centered in those
bounds and turns it about that center; the center of the turned box is the same
point either way. The unturned size is not in the bounds — at an odd multiple of
45° every box whose sides add up to the same length turns to the same square — so
the layout, which sized the node before it turned it, carries it on the rect
(``PenRect/unturnedSize``), and ``PenLayoutEngine/unturnedBox(of:rect:layoutRects:)``
reads it there. An animation's size override is the node's own size: a turned node
is drawn at it, in bounds grown to it turned. (Until leaf `rkYhcz`, 2026-09-27, the
renderer solved the size back from the bounds, and laid the node out again alone
where they could not answer.) Before that, only a node fixed on both axes was drawn at its own size — a
turned auto-sized text was drawn into its bounds — and the layout pinned the bounds'
corner at the anchor, so turned free nodes drew up to 20 pt off Pen
(`render-rotated-free`, `render-text-fills`' `txt-rotated`: MAE 2.6–7.3, now
0.02–0.14; `PenTransformedFreeTests`, leaf `nAuBKh`).

A `group` has no box of its own: its `x`/`y` is the anchor its children are placed
from, and its box is their union
(``PenLayoutEngine/unturnedBox(of:rect:layoutRects:)``), which need
not start at the anchor. `PenRenderer.enter` draws that box centered in the group's
rect and turned about its center like any node's, then moves the context to the
anchor, so the children land at their own rects; the returned draw rect is the box,
measured from the anchor (a layer blur's buffer and a group's shadow bounds take it
as it is). For a group placed by its own `x`/`y` this is the same picture as turning
about the anchor, which the format's editor bakes rotation into: the `blur2`
fixture's group at `(-111.425, 100)` is the local origin of a 299×299 group at
`(-49.5, -49.5)` swung 45° about its own center, and replaying it reproduces that
editor's PNG. In a flex flow the union is centered in the group's slot
(`render-free-groups.pen`, `PenFreeGroupTests`).

> **Correction, 2026-09-27 (leaf `cqBw2i`):** this section used to call a group "the
> one exception", pivoting at the origin of its layout rect, which the layout pinned at
> the anchor. That drew free groups right, but a group in a flex flow was placed with its
> anchor at the slot's corner rather than its union there (MAE 2.55, 5.53 turned), and a
> blurred group lost what reached left of or above its anchor (1.46). See
> <doc:PenEngine>, *Absolute containers and `fit_content`*.

### Compositing
Node-level opacity uses transparency layers to composite children correctly before applying opacity. Per-fill and per-node blend modes are supported across all 16 standard blend modes.

## Animation Overrides

``NodeOverrides`` enables keyframe animation without Woodcase knowing about timelines or keyframes. The consuming app interpolates property values at a given time `t`, builds a `[String: NodeOverrides]` dictionary keyed by node ID, and passes it to the renderer. Overridable properties include position, size, rotation, opacity, enabled state, and fills.

```swift
let overrides: [String: NodeOverrides] = [
    "title": NodeOverrides(opacity: 0.5, y: 10),
    "background": NodeOverrides(fills: .single(.shorthand("#000000"))),
]
let image = PenRenderer.render(document, layoutRects: rects, size: size, overrides: overrides)
```

## Subtree Rendering

The `rootNodeID` parameter scopes rendering to a single node and its descendants. This enables layer-based compositing for animated titles, where different components (background, text, decorations) enter and exit on separate timelines.

When using `render() → CGImage`, coordinates are translated so the subtree renders at the origin. When using `render(into:)`, the node draws at its layout position and the caller manages coordinate translation.

```swift
// Render just the title layer
let titleImage = PenRenderer.render(
    document, layoutRects: rects,
    size: titleSize, rootNodeID: "title-frame-id"
)
```

## Topics

### Public API

- ``PenRenderer``
- ``NodeOverrides``
- ``PenIconFontRegistry``
- ``PenFontRegistry``
- ``PenColorParser``
- ``PenHexColor``
- ``PenSVGPathParser``
- ``PenPath``
- ``PenPathCommand``
- ``PenPoint``
- ``PenBrowserPlaceholder``
- ``ShaderFills``
