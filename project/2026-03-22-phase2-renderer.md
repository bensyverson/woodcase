# Phase 2 — Renderer

**Date:** 2026-03-22
**Status:** Plan 1 complete (Steps 1-8 + smoke test fixes). Plan 2 complete (Steps 9-12).
**Parent:** [Pen-Based Title System](2026-03-21-pen-title-system.md)
**Depends on:** [Phase 1 Implementation](2026-03-22-pen-phase1-implementation.md) (complete)

## Why

Phase 1 gives us the data pipeline: `.pen` JSON → parsed document → resolved variables → expanded refs → layout rects. But a dictionary of rectangles isn't useful to anyone — we need pixels.

The renderer turns a fully-processed `PenDocument` and its computed layout into a `CGImage`. This is the last piece Woodcase needs to be a complete library: parse a `.pen` file, get an image. Everything beyond that (animation, timeline integration, UI) lives in the consuming app.

## Design Goals

1. **Woodcase is a library, not an app.** The renderer's public API should be minimal and composable. The consuming app (FPP) will add animation, compositing, timeline integration, and UI on top.

2. **Animation-ready from day one.** The renderer must accept property overrides so the consuming app can say "render this document, but with node X at opacity 0.3 and position (10, 50)." This is how keyframe animation works: interpolate values externally, pass them in, render.

3. **HDR-aware.** FPP supports two rendering profiles: `display` (sRGB 8-bit) and `hdr` (extended linear sRGB 32-bit float). The renderer must support both color spaces. Hex colors in `.pen` files are sRGB; HDR brightness mapping happens at render time.

4. **Deterministic and stateless.** Same inputs → same output. No caches, no mutable state, no side effects. The consuming app manages caching.

5. **Subtree rendering for layer-based animation.** The renderer must be able to render any node (and its children) in isolation, not just the full document. This enables the consuming app to render each animatable layer to its own image and composite them independently — essential for animated titles where different components (background, text, decorations) enter/exit on separate timelines. The `.pen` format has three natural layer boundaries: **frames** (the primary structural container with explicit bounds and clipping), **components** (`reusable` nodes / `ref` instances, self-contained subtrees), and **groups** (lightweight transform containers). Any node with an `id` can serve as a subtree root.

## Public API

```swift
/// A function that provides images for image fills.
/// The renderer calls this with the URL from the .pen file.
/// Return nil to skip the image fill.
public typealias ImageProvider = @Sendable (String) -> CGImage?

/// Renders a PenDocument to a CGImage.
public enum PenRenderer {

    /// Render a fully-processed document (or a subtree of it) to an image.
    ///
    /// - Parameters:
    ///   - document: A parsed, variable-resolved, ref-expanded document.
    ///   - layoutRects: Pre-computed layout rectangles from PenLayoutEngine.
    ///   - size: The output image size in points.
    ///   - scale: The pixel scale factor (1x, 2x, 3x). Default 1.
    ///   - colorSpace: The color space for rendering. Default sRGB.
    ///   - rootNodeID: If provided, render only this node and its children.
    ///     The node's layout rect defines the origin; coordinates are
    ///     translated so the subtree renders at (0, 0) in the output image.
    ///     Pass nil (default) to render the entire document.
    ///   - overrides: Per-node property overrides (for animation).
    ///   - imageProvider: Callback to load images for image fills. Default returns nil.
    /// - Returns: A rendered CGImage, or nil if the context couldn't be created.
    public static func render(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        size: CGSize,
        scale: CGFloat = 1,
        colorSpace: CGColorSpace? = nil,
        rootNodeID: String? = nil,
        overrides: [String: NodeOverrides] = [:],
        imageProvider: ImageProvider = { _ in nil }
    ) -> CGImage?

    /// Render directly into an existing CGContext.
    ///
    /// Use this when compositing onto a video frame or other surface.
    /// When rootNodeID is provided, only that subtree is drawn. The caller
    /// is responsible for positioning the context (via translate/concat)
    /// before calling — Woodcase draws at the node's layout coordinates.
    public static func render(
        _ document: PenDocument,
        layoutRects: [String: PenRect],
        into context: CGContext,
        rootNodeID: String? = nil,
        overrides: [String: NodeOverrides] = [:],
        imageProvider: ImageProvider = { _ in nil }
    )
}
```

### NodeOverrides — the animation hook

This is how the consuming app plugs in animation. Each override replaces a resolved property value for a specific node during rendering:

```swift
public struct NodeOverrides: Friendly {
    public var x: Double?
    public var y: Double?
    public var width: Double?
    public var height: Double?
    public var rotation: Double?
    public var opacity: Double?
    public var enabled: Bool?
    public var fills: PenFills?
    // ... extend as needed
}
```

The consuming app interpolates keyframes at a given time `t`, builds a `[String: NodeOverrides]` dictionary, and passes it to `render()`. Woodcase doesn't know about keyframes or time — it just renders what it's told.

### Full pipeline usage

```swift
// Parse
let document = try PenParser.parse(contentsOf: url)

// Resolve variables
let resolved = PenVariableResolver.resolve(document, theme: ["mode": "dark"])

// Expand refs
let expanded = PenRefExpander.expand(resolved)

// Layout
let rects = PenLayoutEngine.layout(expanded)

// Render (static)
let image = PenRenderer.render(expanded, layoutRects: rects, size: CGSize(width: 1920, height: 1080))

// Render (animated, at time t)
let overrides = animationEngine.evaluate(at: t) // consuming app's responsibility
let frame = PenRenderer.render(expanded, layoutRects: rects, size: size, overrides: overrides)

// Render individual layers (for animated titles with per-layer compositing)
let backgroundLayer = PenRenderer.render(expanded, layoutRects: rects, size: bgSize, rootNodeID: "background-frame-id")
let titleLayer = PenRenderer.render(expanded, layoutRects: rects, size: titleSize, rootNodeID: "title-text-id")
let decorLayer = PenRenderer.render(expanded, layoutRects: rects, size: decorSize, rootNodeID: "decoration-group-id")
// Consuming app composites these layers with independent timing, opacity, transforms
```

### Render-into-context for FPP integration

FPP's export pipeline works by drawing directly into a `CGContext` backed by a `CVPixelBuffer`. The `render(into:)` variant supports this without allocating an intermediate image:

```swift
// In FPP's WoodcaseFrameProcessor:
let context = CGContext(data: pixelBuffer.baseAddress, ...)
PenRenderer.render(document, layoutRects: rects, into: context, overrides: overrides)
```

### Layer-based rendering for animated titles

For animated titles, the consuming app renders each animatable component separately and composites them with independent timing. The `rootNodeID` parameter makes this possible without any special "layer" abstraction — the consuming app simply decides which nodes are its layers:

```swift
// In FPP's animated title renderer:
// The designer's .pen file has a structure like:
//   Frame "composition" (1920×1080)
//     ├── Frame "background"   ← layer 1
//     ├── Group "lower-third"  ← layer 2
//     │     ├── Rectangle "bar"
//     │     └── Text "name"
//     └── Text "headline"      ← layer 3

// At time t, each layer may be at a different point in its animation:
for layer in animationTimeline.layers {
    let layerOverrides = layer.evaluate(at: t)
    let layerRect = rects[layer.rootNodeID]!
    let layerSize = CGSize(width: layerRect.width, height: layerRect.height)

    if let layerImage = PenRenderer.render(
        document, layoutRects: rects, size: layerSize,
        rootNodeID: layer.rootNodeID, overrides: layerOverrides
    ) {
        // Composite with layer's animated position, opacity, etc.
        mainContext.draw(layerImage, in: layer.animatedRect(at: t))
    }
}
```

This approach works at any level of the node tree — a layer can be a top-level frame, a nested group, a single text node, or a component instance. Woodcase doesn't need to know about layers or animation; it just renders whatever subtree it's asked to render.

## Rendering Capabilities

### What to render (priority order)

| Priority | Capability | Status | Notes |
|----------|-----------|--------|-------|
| P0 | Solid color fills | ✅ | `PenColorParser` + `PenFillRenderer` |
| P0 | Rectangles with corner radii | ✅ | `PenShapeBuilder`, per-corner radii supported |
| P0 | Opacity and enabled/disabled | ✅ | Transparency layers for correct child compositing |
| P0 | Text (plain) | ✅ | Core Text `CTFramesetter`, font fallback to SF Pro |
| P0 | Frames (containers) with clipping | ✅ | Corner-radius-aware clipping |
| P0 | Transforms (rotation, flip) | ✅ | `PenTransformBuilder` |
| P1 | Linear gradients | ✅ | Rotation negated for Pencil convention |
| P1 | Radial gradients | ✅ | Non-circular via context scaling |
| P1 | Strokes (uniform thickness) | ✅ | `PenStrokeRenderer` with join/cap |
| P1 | Drop shadows | ✅ | `PenEffectRenderer`, Y-offset negated for flipped context |
| P1 | Ellipses | ✅ | Including inner radius (donut) and start/sweep angles (pacman) |
| P1 | Rich text (per-span styling) | ✅ | Per-span font, color, underline, strikethrough |
| P1 | Text alignment (horizontal + vertical) | ✅ | All 4 horizontal + 3 vertical modes |
| P2 | Angular gradients | ✅ | Per-pixel bitmap rendering (not native API) |
| P2 | Image fills | ✅ | stretch/fill/fit modes via `imageProvider` callback (Plan 2) |
| P2 | SVG paths | ✅ | `PenSVGPathParser`, all commands including arcs |
| P2 | Blur effects | ✅ | Offscreen CIGaussianBlur |
| P2 | Per-side strokes | ❌ | Not implemented |
| P2 | Dashed strokes | ❌ | Not implemented (Pencil MCP drops `dashPattern`) |
| P2 | Polygons | ✅ | Regular n-gon path generation |
| P2 | Blend modes | ✅ | 16 blend modes mapped |
| P2 | Inner shadows | ✅ | Inverted path + even-odd fill |
| P2 | Multiple fills | ✅ | Bottom-to-top stacking |
| P3 | Stroke alignment (inside/outside/center) | ✅ | All 3 modes |
| P3 | Text decorations (underline, strikethrough) | ✅ | Underline native CT, strikethrough manual drawing |
| P3 | Shadow spread | ✅ | Stroked path expansion |
| P3 | HDR brightness mapping | ❌ | Not implemented |
| -- | Mesh gradients | ❌ | Graceful skip (model preserved for round-trip) |
| -- | Background blur | ❌ | Requires compositing context from consuming app |
| -- | Icon fonts | ❌ | Deferred; agents use SVG paths instead |

### Rendering order per node

1. **Check enabled** — skip if `enabled == false`
2. **Save graphics state** — `CGContextSaveGState`
3. **Apply transforms** — translate to position, rotate, flip
4. **Build shape path** — rectangle (with corner radii), ellipse, polygon, SVG path
5. **Render fills** — bottom-to-top, each fill clips to shape path
6. **Render stroke** — on top of fills, with thickness/join/cap/dash
7. **Render effects** — shadows, blur
8. **Render children** — recursively, clipped to frame bounds if `clip: true`
9. **Restore graphics state**

## SVG Path Parsing

`PathData.geometry` stores raw SVG path strings (e.g. `"M 10 10 L 20 20 Q 30 30 40 40 Z"`). We need a parser to convert these to `CGPath`.

SVG path commands to support:

| Command | Meaning | Absolute/Relative |
|---------|---------|-------------------|
| M/m | Move to | Both |
| L/l | Line to | Both |
| H/h | Horizontal line | Both |
| V/v | Vertical line | Both |
| C/c | Cubic bezier | Both |
| S/s | Smooth cubic | Both |
| Q/q | Quadratic bezier | Both |
| T/t | Smooth quadratic | Both |
| A/a | Elliptical arc | Both |
| Z/z | Close path | — |

This is a well-defined specification. We should implement it ourselves (no dependency) as a `SVGPathParser` that returns a `CGPath`. This is a self-contained piece of work that can be tested independently.

## Color Parsing

Hex colors in `.pen` files follow these formats:
- `#RGB` (3 chars) → expand to `#RRGGBB`
- `#RRGGBB` (6 chars)
- `#RRGGBBAA` (8 chars) → last two are alpha

We need a `PenColorParser` (or extend the existing `CSSColorParser` in FPP if it's available) that converts hex strings to `CGColor`. For HDR rendering, the same hex value is interpreted in extended linear sRGB.

## Snapshot Testing Strategy

Visual testing against Pencil's rendered output:

1. **Generate reference images from Pencil MCP** — for each test fixture, use Pencil's `get_screenshot` to produce a reference PNG.
2. **Render the same fixture with PenRenderer** — parse the `.pen` file, run the full pipeline, render to `CGImage`.
3. **Compare** — pixel-by-pixel comparison with a tolerance threshold (we won't match exactly due to font rendering differences, anti-aliasing, etc.).

For CI, snapshot tests have the same Core Text limitation as text measurer tests — they need a hosted environment. We should also have **unit tests for individual rendering operations** (color parsing, SVG path parsing, gradient construction, blend mode mapping) that run via `swift test`.

### Test categories

| Category | Tests via `swift test` | Tests via Xcode |
|----------|----------------------|-----------------|
| Color parsing (hex → CGColor) | Yes | — |
| SVG path parsing (string → CGPath) | Yes | — |
| Blend mode mapping | Yes | — |
| Gradient construction | Yes | — |
| Full-frame rendering | — | Snapshot tests |
| Text rendering | — | Snapshot tests |
| Compositing/clipping | — | Snapshot tests |

## Implementation Plans

The implementation is split into two plans. Plan 1 delivers a working renderer for common .pen content. Plan 2 layers on the animation/integration API, visual validation, and documentation.

### Plan 1 — Rendering foundations + core pipeline (Steps 1-8) ✅ COMPLETE

Detailed plan and execution notes: [Plan 1 doc](2026-03-23-plan1-renderer-foundations.md)

**323 tests, all passing.** All P0/P1/P2/P3 rendering capabilities implemented except image fills, dashed strokes, per-side strokes, and HDR.

### Plan 2 — Integration + polish (Steps 9-12) ✅ COMPLETE

Detailed plan and execution notes: [Plan 2 doc](#plan-2-execution-details) (below)

**353 tests, all passing.** New test count breakdown: 8 image fill + 4 NodeOverrides model + 8 override rendering + 6 subtree rendering + 3 snapshot comparison + 1 rotation layout = 30 new tests. Snapshot MAE scores: shapes 0.016, gradients 0.155, transforms 1.12.

---

### Steps 1-8: Complete

See [Plan 1 doc](2026-03-23-plan1-renderer-foundations.md) for detailed progress, discoveries, and design decisions.

### Step 9: Image Fills ✅

Wired `imageProvider` through `PenRenderer` → `PenFillRenderer`. Implemented stretch, fill (aspect-fill + clip), and fit (aspect-fit + center) modes. 8 tests.

### Step 10: NodeOverrides & rootNodeID ✅

Created `NodeOverrides` struct with x/y/width/height/rotation/opacity/enabled/fills overrides. Changed `overrides` parameter type from `[String: [String: Any]]` to `[String: NodeOverrides]`. Applied overrides in `renderNode()` before rendering. Added `findNode(id:in:)` DFS helper for `rootNodeID` subtree rendering. 18 tests.

### Step 11: Snapshot Tests & Visual Validation ✅

Implemented MAE (mean absolute error) comparison helper. Added automated snapshot tests for 3 fixture categories (text excluded — Core Text and Pencil produce inherently different font rasterization, so pixel comparison is not meaningful). Re-exported transforms-and-effects reference at 2x from Pencil MCP.

During visual validation, found and fixed three rendering bugs:
1. **Rotation bounding box** — layout engine was not expanding rotated nodes to their axis-aligned bounding box, causing incorrect positioning and sizing
2. **Shadow/blur scale** — CG's `setShadow` offset and blur are in device pixels (not user space), so they need explicit `* scale` at render time
3. **Blur offscreen buffer** — was rendering at 1x regardless of context scale, making blur appear half-sized at 2x

Final MAE scores: shapes 0.016, gradients 0.155, transforms 1.12.

### Step 12: Documentation ✅

Updated PenRendering.md with image fills, NodeOverrides, and subtree rendering sections. Added `NodeOverrides` to Woodcase.md topic group. Updated project docs with Plan 2 completion status.

## Execution Discoveries (Plans 1 + 2)

Key findings from implementation and snapshot validation:

### Gradient Direction Convention
Pencil's gradient rotation convention required negating the angle in our renderer:
- **Linear:** rotation=0 means bottom-to-top; rotation=90 means stop 0 on the RIGHT (not left). We negate the angle before computing the direction vector.
- **Angular:** Same negation needed for rotation offset.

### Angular Gradient Rendering
The original plan suggested `CGContext.drawConicGradient` (design decision #4). This API doesn't exist in a usable form for our setup. We tried pie-slice rendering (360/720 segments) but it produces visible moiré artifacts. **Final solution: per-pixel bitmap rendering** — compute angle from center for each pixel, interpolate color, draw as CGImage. Artifact-free at any zoom level.

### Font Fallback
When a .pen file specifies a font family not installed on the system (e.g. "Inter"), Core Text silently falls back to Helvetica, which **ignores weight and style traits** (bold/italic have no effect). Our fix: `PenTextMeasurer.resolveFont` now checks if the requested family is available and falls back explicitly to SF Pro, which correctly applies all traits.

### Text Color from Multiple Fills
Text nodes can have multiple fills (e.g. `["#F0F0F0", "#000000"]`). The text foreground color should be the **last** solid color fill (topmost in the stack), not the first. This matches Pencil's behavior.

### Strikethrough
Core Text has no native strikethrough attribute (`kCTStrikethroughStyleAttributeName` does not exist). Implemented via custom attribute key + manual line drawing after `CTFrameDraw`, iterating CTFrame lines/runs.

### Text Wrapping in Flex Layout
`fill_container` text nodes in vertical flex layouts need the parent's resolved cross-axis width during the first measurement pass. Without it, the text measures as single-line (width=0 fallback), and the computed height is too small for wrapped text. Fixed by pre-resolving the parent's cross-axis content size and passing it to child measurement.

### Rich Text Layout Measurement
When a text node has rich text spans with mixed font weights/styles, the layout engine must measure using the widest font properties (heaviest weight, italic if any span uses it, largest font size) to avoid clipping. The actual rendering uses per-span fonts, which may be wider than the node-level defaults.

### Rich Text Spans in Pencil
The .pen schema supports rich text content arrays (per-span fontWeight, fontStyle, fill, etc.), but **Pencil.dev itself does not implement this feature**. The MCP can't persist or display rich text spans. Our fixture files have rich text content written as raw JSON. Woodcase renders rich text correctly — we're ahead of Pencil on this.

### Shadow Y-Offset in Flipped Context
CG shadow offset operates in the original CG coordinate space (y-up). Since our context is flipped (y-down), shadow Y-offsets must be negated.

### Blur via Offscreen + CIGaussianBlur
Blur renders the node into an offscreen bitmap context with padding (`ceil(radius * 3)`), applies `CIGaussianBlur`, and draws the result back. Uses `CIContext(options: [.useSoftwareRenderer: true])` for reliable headless rendering. CoreImage is imported but doesn't need explicit framework linking in Package.swift.

### Rotation Bounding Box in Layout
Pencil's layout engine applies rotation transforms before computing the final bounding box. An 80×80 rectangle rotated 45° occupies 113.14×113.14 in layout. Our `PenLayoutEngine` now applies the same expansion via `applyRotationExpansion()`. The renderer then draws the original (unrotated) shape centered within the expanded bounding box, and the rotation transform produces the correct visual result.

### CG setShadow is in Device Space
`CGContext.setShadow(offset:blur:)` operates in device pixels, **not** user space. This means at 2x scale, an offset of `(4, 4)` only moves the shadow 4 device pixels (= 2 points). Both offset and blur must be multiplied by `abs(context.ctm.a)` to get correct point-based behavior. This was not obvious from Apple's documentation.

### CIGaussianBlur Offscreen Buffer Must Match Context Scale
The blur effect renders into an offscreen bitmap context, applies `CIGaussianBlur`, and composites back. The offscreen buffer must be created at the same scale as the main context (e.g. 2x), otherwise the blur appears half-sized. However, the CIGaussianBlur `inputRadius` should use the **unscaled** point value — the higher-resolution buffer already provides the correct pixel density. The padding, buffer dimensions, and draw-back coordinates all need scale adjustment.

### Inner Shadows in Pencil
Pencil's .pen format supports inner shadows (`shadowType: "inner"`), and Woodcase renders them correctly using the inverted-path technique. However, Pencil's own UI barely renders inner shadows visibly. The remaining MAE difference (~1.12) on the transforms fixture is partly due to this: Woodcase faithfully renders the inner shadow while Pencil appears to nearly ignore it.

### Text Excluded from Snapshot Tests
Core Text and Pencil's renderer (likely Skia/web-based) produce inherently different font rasterization, anti-aliasing, and hinting. Pixel comparison is not meaningful for text-heavy fixtures. Text rendering is validated visually via the smoke tests (which export PNGs to `/tmp/pen-exports/` for manual inspection). The text fixture MAE was ~4.9, which is respectable but not suitable for regression gating.

### Reference PNG Scale Matters
Pencil's `export_nodes` MCP tool supports a `scale` parameter (default 2). All reference PNGs must be exported at the same scale used by `PenRenderer.render()` (currently 2x in smoke/snapshot tests). Two of the original reference PNGs were at 1x, causing large MAE scores until re-exported at 2x.

## Current File Structure

```
Sources/Woodcase/Rendering/
├── PenColorParser.swift           (public) hex → CGColor
├── PenBlendMode+CGBlendMode.swift (public) PenBlendMode → CGBlendMode
├── PenSVGPathParser.swift         (public) SVG path string → CGPath
├── PenShapeBuilder.swift          (internal) node → CGPath
├── PenFillRenderer.swift          (internal) solid + gradient + image fills
├── PenStrokeRenderer.swift        (internal) stroke rendering
├── PenRenderer.swift              (public) main API + tree walk + subtree rendering
├── PenTransformBuilder.swift      (internal) rotation + flip
├── PenTextRenderer.swift          (internal) Core Text rendering
└── PenEffectRenderer.swift        (internal) shadows + blur (scale-aware)

Sources/Woodcase/Models/
├── NodeOverrides.swift            (public) per-node animation overrides
└── ... (other model files)

Tests/WoodcaseTests/
├── PenColorParserTests.swift      16 tests
├── PenBlendModeTests.swift        19 tests
├── PenSVGPathParserTests.swift    33 tests
├── PenShapeBuilderTests.swift     14 tests
├── PenFillRendererTests.swift     7 tests
├── PenTransformBuilderTests.swift 6 tests
├── PenRendererTests.swift         17 tests
├── PenTextRendererTests.swift     7 tests
├── PenEffectRendererTests.swift   5 tests
├── PenRendererSmokeTests.swift    4 tests (full-pipeline, exports PNGs, logs MAE)
├── PenImageFillTests.swift        8 tests (stretch/fill/fit modes)
├── NodeOverridesTests.swift       4 tests (model conformance)
├── PenNodeOverrideTests.swift     8 tests (override rendering behavior)
├── PenSubtreeRenderTests.swift    6 tests (rootNodeID subtree rendering)
├── PenSnapshotTests.swift         3 tests (MAE comparison vs Pencil references)
├── PenSnapshotTestHelpers.swift   MAE comparison helper
└── PenLayoutEngineTests.swift     26+ tests (includes rotation bounding box)

Tests/WoodcaseTests/Fixtures/
├── render-shapes-and-fills.pen    (rebuilt 2026-03-23: 3 rows, 14 shapes)
├── render-shapes-and-fills.png    (re-exported @2x from Pencil)
├── render-gradients.pen           (6 originals + 2 extras)
├── render-gradients.png           (@2x from Pencil)
├── render-transforms-and-effects.pen
├── render-transforms-and-effects.png  (re-exported @2x from Pencil, 2026-03-23)
├── render-text.pen                (includes rich text spans as raw JSON)
├── render-text.png                (1x — not used in snapshot tests)
└── layout-*.pen/layout.json/png   (25 layout test fixtures)
```

## Design Decisions

1. **Image loading: provider callback, no internal caching.** The renderer accepts an `imageProvider: (String) -> CGImage?` callback. The consuming app controls loading, caching, and error handling. Woodcase doesn't cache images — caching is a policy decision that belongs to the caller. If the provider returns nil, the image fill is skipped.

2. **Per-fill blend modes: transparency layers.** Use `CGContextBeginTransparencyLayer` for nodes with fills. Each fill composites within the layer using its own blend mode. The completed layer composites onto the main context using the node's overall blend mode. This is the correct approach — Core Graphics optimizes the simple case internally.

3. **Stroke alignment: simple shapes only.** Inside/outside stroke alignment is implemented for rectangles, ellipses, and polygons (inset/outset the shape, clip to original boundary). For SVG paths, fall back to center alignment. Path offsetting for arbitrary curves is a hard computational geometry problem that doesn't justify the effort for the title use case.

4. **Angular gradients: per-pixel bitmap rendering.** ~~Originally planned to use `CGContext.drawConicGradient`~~ — this API doesn't work cleanly with our coordinate setup. Pie-slice approaches (360-720 segments) produce visible moiré artifacts. Final approach: render per-pixel into a bitmap (compute angle from center, interpolate color), draw as CGImage. Artifact-free at any zoom level, ~100 lines of code.

5. **Subtree rendering via `rootNodeID`, not a dedicated "layer" API.** Rather than introducing a layer abstraction, the renderer accepts an optional `rootNodeID` that scopes rendering to a single node and its descendants. This keeps Woodcase's API minimal — the consuming app decides what constitutes a "layer" based on its animation needs. The `.pen` format's natural boundaries (frames, components, groups) all work as subtree roots without Woodcase needing to know about them. The `render() → CGImage` variant translates coordinates so the subtree renders at `(0, 0)`; the `render(into:)` variant draws at the node's layout position, leaving coordinate translation to the caller.

6. **Text baselines: use our own, compensate if needed.** Core Text is authoritative for both measurement and rendering, so text is internally consistent. If comparison with Pencil reveals a predictable offset, we can add an optional `baselineAdjustment` parameter — but we won't build that machinery until we observe an actual problem.

## Integration with FPP

FPP's rendering architecture is already pluggable. The integration path:

```
FPP: GraphicsCoordinator (preview)
     GraphicsFrameProcessor (export)
         ↓
     "Is this a .pen instance?"
         ↓ yes                    ↓ no
     PenRenderer.render(         GraphicsRenderer.renderFrame(
         document,                   runtime, params, scene
         layoutRects: rects,     )
         into: context,
         overrides: animOverrides
     )
```

**What FPP adds on top of Woodcase:**
- **Animation engine** — keyframe interpolation, expression evaluation → `[String: NodeOverrides]`
- **Scene parameters** — normalized time `t`, transcript words, audio amplitude
- **Compositing** — layering multiple graphics onto a video frame, including per-layer rendering via `rootNodeID` for animated titles
- **Caching** — parsed documents, resolved states, layout rects cached per instance
- **UI** — template browser, parameter inspector, timeline keyframe editor

**What Woodcase provides:**
- Parse → Resolve → Expand → Layout → Render
- Each step is a pure function
- The consuming app composes them however it needs
