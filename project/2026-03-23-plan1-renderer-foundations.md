# Plan 1: Rendering Foundations + Core Pipeline

**Date:** 2026-03-23
**Status:** Complete — All steps (0-9) done
**Parent:** [Phase 2 Renderer](2026-03-22-phase2-renderer.md)

## Context

Woodcase's pipeline currently ends at layout: Parse → Resolve → Expand → Layout → `[String: PenRect]`. This plan adds the final stage — rendering a `PenDocument` + layout rects into pixels via CoreGraphics. It covers steps 1-8 of the Phase 2 Renderer design doc, delivering a working renderer for all common .pen content (shapes, fills, gradients, text, effects). Plan 2 (later) adds image fills, NodeOverrides/rootNodeID wiring, snapshot tests, and documentation polish.

## Progress

| Step | Description | Status | Files Created |
|------|------------|--------|---------------|
| 0 | Test fixtures via Pencil MCP | **Done** | 4 `.pen` + 4 `.png` in `Fixtures/` |
| 1 | Color Parser | **Done** | `Rendering/PenColorParser.swift`, `PenColorParserTests.swift` (16 tests) |
| 2 | Blend Mode Mapping | **Done** | `Rendering/PenBlendMode+CGBlendMode.swift`, `PenBlendModeTests.swift` (19 tests) |
| 3 | SVG Path Parser | **Done** | `Rendering/PenSVGPathParser.swift`, `PenSVGPathParserTests.swift` (33 tests) |
| 4 | Shape Rendering + Renderer Skeleton | **Done** | `Rendering/PenShapeBuilder.swift`, `PenRenderer.swift`, `PenFillRenderer.swift`, `PenStrokeRenderer.swift`, `PenShapeBuilderTests.swift` (14 tests), `PenRendererTests.swift` (17 tests) |
| 5 | Gradient Rendering | **Done** | Extended `PenFillRenderer.swift`, `PenFillRendererTests.swift` (7 tests) |
| 6 | Transform & Compositing | **Done** | `Rendering/PenTransformBuilder.swift`, `PenTransformBuilderTests.swift` (6 tests) |
| 7 | Text Rendering | **Done** | `Rendering/PenTextRenderer.swift`, `PenTextRendererTests.swift` (7 tests) |
| 8 | Clipping & Effects | **Done** | `Rendering/PenEffectRenderer.swift`, `PenEffectRendererTests.swift` (5 tests) |
| 9 | Documentation | **Done** | `Documentation.docc/PenRendering.md`, updated `Woodcase.md`, `PenEngine.md`, `README.md` |

**Test count at handoff:** 319 tests, all passing.

## File Structure

All new rendering source files go in `Sources/Woodcase/Rendering/` (created). Each test in a new file under `Tests/WoodcaseTests/`.

```
Sources/Woodcase/Rendering/
├── PenColorParser.swift           ✅ Step 1: hex -> CGColor
├── PenBlendMode+CGBlendMode.swift ✅ Step 2: PenBlendMode -> CGBlendMode
├── PenSVGPathParser.swift         ✅ Step 3: SVG path string -> CGPath
├── PenShapeBuilder.swift          ✅ Step 4: node kind -> CGPath
├── PenFillRenderer.swift          ✅ Steps 4+5: solid color + gradient fills
├── PenStrokeRenderer.swift        ✅ Step 4: stroke rendering
├── PenRenderer.swift              ✅ Step 4+6: main API + tree walk + transforms
├── PenTransformBuilder.swift      ✅ Step 6: rotation + flip -> CGAffineTransform
├── PenTextRenderer.swift          ✅ Step 7: Core Text rendering
└── PenEffectRenderer.swift        ✅ Step 8: shadows, blur

Tests/WoodcaseTests/
├── PenColorParserTests.swift      ✅ 16 tests
├── PenBlendModeTests.swift        ✅ 19 tests
├── PenSVGPathParserTests.swift    ✅ 33 tests
├── PenShapeBuilderTests.swift     ✅ 14 tests
├── PenFillRendererTests.swift     ✅ 7 tests
├── PenTransformBuilderTests.swift ✅ 6 tests
├── PenRendererTests.swift         ✅ 17 tests (integration)
├── PenTextRendererTests.swift     ✅ 7 tests
└── PenEffectRendererTests.swift   ✅ 5 tests

Tests/WoodcaseTests/Fixtures/
├── render-shapes-and-fills.pen    ✅ (rebuilt: 14 shapes + 3 paths in separate artboard)
├── render-shapes-and-fills.png    ✅ (re-exported @2x after rebuild)
├── render-gradients.pen           ✅ (6 originals + 2 extras: opacity, blend mode)
├── render-gradients.png           ✅
├── render-transforms-and-effects.pen ✅
├── render-transforms-and-effects.png ✅
├── render-text.pen                ✅
└── render-text.png                ✅

scripts/
└── probe-pixels.swift             ✅ Extracts RGBA values from PNGs at given coordinates
```

## Discoveries During Execution

### Pencil MCP Limitations (Step 0)
- **Rich text content arrays** (spans with per-span fontWeight/fontStyle) don't persist through Pencil MCP — `batch_get` returns empty content. The `.pen` fixture files were manually written with rich text spans.
- **Inner shadows** (`shadowType: "inner"`) revert to `"outer"` when saved — Pencil MCP doesn't appear to support inner shadows. The `.pen` fixture was manually corrected.
- **`dashPattern`** on strokes was silently dropped by Pencil MCP.
- **Per-span `fill`** is not a valid TextStyle property in Pencil's schema (though our Woodcase model supports it via `PenTextSpan.fill`).
- **`blendMode`** is a property on fills (not on nodes directly) in Pencil's schema. The fixture uses `fill: {type: "color", color: "#0000FF", blendMode: "multiply"}`.
- **Reference PNGs** are accurate for what Pencil renders, but do NOT show rich text spans, inner shadows, or dash patterns since Pencil didn't persist those features.

### .pen File Version
- The current Pencil format version is `"2.9"`. Using older versions like `"0.0.1"` or `"0.3"` causes "Unsupported file format" errors when opening in Pencil.
- **Note:** The existing `layout-*.pen` and `parser-*.pen` fixtures use `"0.0.1"` — they parse fine in Woodcase but won't open in Pencil. If we ever need to re-export those, they'll need version updates too.

### Stroke Alignment Default
- **Stroke `align` defaults to `"inside"`** in Pencil (not `"center"`). A line node with the default stroke alignment is invisible because lines have no interior. Always set `align: "center"` on line strokes. Our renderer handles this correctly — "inside" stroke on a line draws nothing visible.

### Pencil Path Normalization
- **Pencil normalizes SVG paths** to compact relative notation. Absolute commands like `M 60 0 L 74 42` become `M60 0l14 42`. Our SVG path parser handles this compact form, including negative-number-as-separator (`M10-20` = `M 10 -20`).

### Pencil Default Font
- Pencil defaults text to `fontFamily: "Inter"`, `fontSize: 14`, `fontWeight: "normal"`. Our `PenTextMeasurer` defaults to `"SF Pro"` at 16pt — this is intentional (we use the system font as fallback), but be aware that fixture text nodes explicitly specify Inter.

### Fixture Rebuild (Step 4)
- The original `render-shapes-and-fills.pen` fixture lost its children between sessions (empty frame). Had to rebuild all shape nodes from scratch.
- Discovered orphaned nodes from the previous session that overlapped new content — deleted them.
- The frame was originally 800×600 but needed resizing to 850×530 to fit all three rows of test shapes.
- Pencil's `line` node type does not render in screenshots when stroke alignment is `"inside"` (the default). Lines need explicit `align: "center"` to be visible.

### Gradient Rendering (Step 5)
- Angular (conic) gradients don't have a native CG API that works cleanly with our coordinate setup. Implemented via 360 pie-slice segments with color interpolation — visually smooth and matches Pencil's output.
- Pencil's linear gradient convention: rotation=0 means bottom-to-top (stop position 0 at bottom, 1 at top). Rotation goes clockwise: 90° = left-to-right.
- Added gradient-opacity and gradient-blendmode test nodes to the gradients fixture during Step 5.

### Transform & Compositing (Step 6)
- Opacity is implemented via `CGContext.beginTransparencyLayer()` / `endTransparencyLayer()` rather than just `setAlpha()` — this ensures children of a frame with opacity are composited together before the opacity is applied, matching Pencil's behavior.
- Rotation in .pen is counter-clockwise in degrees. In our flipped coordinate system (y-down), we negate the angle when converting to radians for CG.

### Text Rendering (Step 7)
- **Core Text coordinate re-flip:** The CGContext is already flipped (y-down) by PenRenderer. Core Text draws bottom-up. PenTextRenderer applies a local re-flip (translate + scaleY=-1) before CTFrameDraw, then restores state.
- **Vertical alignment via translate:** Vertical alignment offset is applied as a context translation *before* the Core Text re-flip, in visual (y-down) space. This is simpler and more correct than manipulating the CTFrame path rect's origin.
- **Text color extraction:** The first solid color fill (shorthand or color fill) is used as the foreground color attribute. Gradient fills on text are not supported. Default is opaque black.
- **CTParagraphStyleSetting pointer safety:** Swift 6 flags temporary pointer conversions in `CTParagraphStyleSetting`. Used `withUnsafeMutablePointer` pattern (matching PenTextMeasurer) to keep pointers valid for the scope.
- **CFStringGetLength over NSString.length:** `NSString` bridging isn't available without Foundation's `import Foundation` in some contexts. Used `CFStringGetLength` for span length calculation.

### Clipping & Effects (Step 8)
- **Shadow Y-offset negation:** CG shadow offset operates in the original CG coordinate space (y-up). Since our context is flipped (y-down), we negate the Y component of shadow offsets so shadows cast in the visually correct direction.
- **Inner shadow technique:** Clip to shape, create inverted path (large rect + shape with even-odd fill rule), set CG shadow, fill inverted path. Shadow falls inward from the inverted edge. Works reliably in flipped context.
- **Blur via CIGaussianBlur:** Renders node content into an offscreen bitmap context with padding (`ceil(radius * 3)`), applies `CIGaussianBlur` filter, draws result back. Uses `CIContext(options: [.useSoftwareRenderer: true])` for reliable headless rendering.
- **Spread via stroked expansion:** Shadow spread is implemented by expanding the shape path via `CGPath.copy(strokingWithWidth:)` and drawing it with the shadow before the main content.
- **Frame clipping already works:** Corner-radius clipping was already handled by PenShapeBuilder generating rounded paths, used by the existing clip code. No additional work needed.
- **Effects extraction pattern:** Added `effects(for:)` helper matching the existing `blendMode(for:)` pattern — switch on all 8 node kinds to extract `data.effects`.
- **Closure-based effect integration:** Node content drawing is wrapped in a closure so blur can redirect it to an offscreen context. Outer shadows are applied before the closure, inner shadows after.

### Pixel Probing for Test Values
- Created `scripts/probe-pixels.swift` to extract RGBA values from reference PNGs at specific coordinates. This makes test expectations traceable and reproducible — re-run the script if fixtures change.
- The script uses sRGB color space and handles premultiplied alpha (un-premultiplies for the output).
- Pencil exports at @2x scale, so logical coordinates must be doubled when probing.

## Steps (Remaining)

Each step follows strict TDD: write failing tests, confirm they fail, implement, confirm they pass, run full suite.

### Step 7: Text Rendering
**Files:** `Rendering/PenTextRenderer.swift`, `PenTextRendererTests.swift`

```swift
enum PenTextRenderer {
    static func renderText(_ textData: PenNode.TextData, rect: PenRect, fills: PenFills?, in context: CGContext)
}
```

- **Reuse** `PenTextMeasurer.resolveFont(family:size:weight:style:)` for font resolution
- **Plain text:** build `CFAttributedString` with font + letter spacing + line height, create `CTFramesetter` + `CTFrame`, draw
- **Rich text:** build `CFMutableAttributedString` concatenating spans, each with font/color overrides, fallback to node-level properties
- **Horizontal alignment:** via `CTParagraphStyle` (.alignment)
- **Vertical alignment:** measure text height via `PenTextMeasurer.measureCFAttributedString()`, offset origin (top=0, middle=(rect-text)/2, bottom=rect-text)
- **Text color:** from fills — first solid color fill as `kCTForegroundColorAttributeName`
- Wire into `PenRenderer.renderNode()` for `.text` case

- **Tests (may need Xcode for font server):** Plain text renders (non-zero pixels), center alignment, vertical middle alignment, rich text with two spans, per-span colors, empty text -> no crash

### Step 8: Clipping & Effects
**Files:** `Rendering/PenEffectRenderer.swift`, `PenEffectRendererTests.swift`

- **Frame clipping:** Already partially implemented in Step 4 (clip to frame bounds). May need refinement for corner-radius clipping.
- **Outer shadows:** `CGContext.setShadow(offset:blur:color:)` set *before* drawing fills/strokes (CG creates shadow automatically). Parse shadow color via PenColorParser.
- **Inner shadows:** Clip to shape, create inverted path (large rect - shape), set shadow, fill inverted path. Well-known CG technique.
- **Blur:** Render node into offscreen bitmap context, create `CIImage`, apply `CIGaussianBlur`, draw result back. Requires `import CoreImage`.

Render order per node becomes: check enabled -> save state -> transform/opacity/blend -> if outer shadow: set shadow -> shape + fills + stroke -> clear shadow -> if inner shadow: render pass -> if clip: clip to bounds -> children -> restore -> if blur: was offscreen, blur + composite

- **Tests:** Frame clip: child beyond bounds invisible (already tested in Step 4), outer shadow: pixels outside shape, inner shadow: darkened edge pixels, blur: averaged pixels, disabled effect: no effect, multiple effects

### Step 9: Documentation
Update alongside each step (100% DocC coverage on all public APIs):
- `PenEngine.md`: Add "Stage 5: Rendering" section
- `Woodcase.md`: Add "Rendering" topic group with `PenRenderer`, `PenColorParser`, `PenSVGPathParser`
- New `PenRenderer.md` DocC article: rendering architecture overview

## Key Design Decisions

1. **Coordinate flip at context creation** — CG is bottom-left origin, .pen is top-left. Flip once at the top via translate+scale, then everything draws in top-left space.
2. **Stateless enum pattern** — `PenRenderer`, `PenColorParser`, `PenSVGPathParser` are all `enum` with static methods, matching existing pipeline stages.
3. **Rendering helpers are internal** — `PenShapeBuilder`, `PenFillRenderer`, `PenStrokeRenderer`, `PenTransformBuilder`, `PenTextRenderer`, `PenEffectRenderer` are `internal` (not public). Only `PenRenderer`, `PenColorParser`, `PenSVGPathParser`, and the `PenBlendMode` extension are public.
4. **API params for Plan 2 included now** — `rootNodeID`, `overrides`, `imageProvider` are in the signature with defaults, but not wired up until Plan 2.
5. **Package.swift may need CoreImage** — Step 8 blur uses `CIFilter`. If it requires explicit linking, add `.linkedFramework("CoreImage")` conditional on macOS/iOS.
6. **Pixel probing for test values** — Test expectations are generated from Pencil reference PNGs via `scripts/probe-pixels.swift`, making them traceable and reproducible.
7. **Angular gradient via pie slices** — No native CG conic gradient API fit our needs, so we render 360 pie-slice segments with interpolated colors. Matches Pencil's output.
8. **Transparency layers for opacity** — Node opacity uses `beginTransparencyLayer()` to ensure children composite correctly before opacity is applied.

## Verification

After each step:
1. `swift test --quiet` — all tests pass
2. `swiftformat . --lint` — no formatting issues

After all steps:
1. Full test suite green
2. `swift package generate-documentation --target Woodcase` — builds without warnings
3. Integration test: parse each `render-*.pen` fixture, run full pipeline through render, visually compare output CGImage against the corresponding `render-*.png` reference from Pencil
