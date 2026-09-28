# Pen Renderer Test Corpus

**Date:** 2026-03-22
**Status:** Draft — pending review
**Parent:** [Pen-Based Title System](2026-03-21-pen-title-system.md)

## Why

We're building a renderer for the .pen format from scratch. The renderer must agree with Pencil's own rendering — it's the canonical implementation. Rather than building our renderer and then manually checking if things "look right," we can use Pencil's MCP tools as an oracle: create test .pen files in Pencil, capture Pencil's computed layout and rendered screenshots, and use those as ground truth for our implementation.

This is strict TDD: build the test fixtures before writing any implementation code, then implement until the tests pass.

## Approach

Pencil's MCP server exposes three tools that give us ground truth:

| Tool | What it gives us | Test layer it validates |
|------|-----------------|----------------------|
| `batch_design` | Creates .pen files with precise node structures | PenParser (do we parse what Pencil writes?) |
| `snapshot_layout` | Computed layout rects for every node (x, y, width, height) | PenLayoutEngine (exact numeric comparison) |
| `get_screenshot` | Rendered PNG of any node | PenRenderer (visual/perceptual comparison) |

The layout snapshots are the crown jewel — they're exact numbers, not pixels. If Pencil says a node is at `{x: 24, y: 16, w: 352, h: 48}`, our layout engine must compute the same values. No visual ambiguity, no tolerance thresholds.

### Workflow for each test case

1. **Design** the test case in Pencil using `batch_design` — a minimal .pen structure that isolates a specific feature.
2. **Capture layout** via `snapshot_layout` — save the computed rects as expected values.
3. **Capture screenshot** via `get_screenshot` — save the PNG as a visual reference.
4. **Export the .pen JSON** via `batch_get` with full depth — save as the test input fixture.
5. **Write the test** — assert our parser, layout engine, or renderer produces the same output.

### Fixture storage

```
FirstPassProTests/
└── PenEngine/
    └── Fixtures/
        ├── basic-shapes.pen              ← .pen JSON input
        ├── basic-shapes.layout.json      ← snapshot_layout output (expected rects)
        ├── basic-shapes.png              ← get_screenshot output (visual reference)
        ├── text-variations.pen
        ├── text-variations.layout.json
        ├── text-variations.png
        └── ...
```

Each fixture is a triplet: `.pen` (input), `.layout.json` (layout ground truth), `.png` (visual ground truth).

## Test Matrix

### 1. Parser Tests

These validate that `PenParser` correctly converts .pen JSON into our Swift `PenDocument` model. No ground truth images needed — we assert structural correctness against the input JSON.

| Test case | What it exercises |
|-----------|-------------------|
| **Empty document** | Minimal valid .pen: version + empty children |
| **All node types** | One of each: frame, rectangle, ellipse, text, path, group, line, polygon, ref |
| **Nested children** | Frame containing frames containing shapes — verify tree structure |
| **Fill types** | Solid color, gradient (linear/radial/angular), image fill on a single node |
| **Multiple fills** | Array of fills on one node — verify ordering preserved |
| **Stroke variants** | Uniform thickness, per-side thickness, dash pattern, join/cap |
| **Effect variants** | Outer shadow, inner shadow, blur, multiple effects |
| **Text content** | Plain string, rich text spans (array of TextStyle), all textGrowth modes |
| **Variables block** | All four variable types (boolean, color, number, string) |
| **Theme-aware variables** | Variables with theme-conditional values |
| **Reusable + ref** | Component with `reusable: true`, ref with descendant overrides |
| **Nested refs** | Ref inside a ref — descendant path resolution with `/` separator |
| **Imports** | Import declaration parsing (we don't need to resolve cross-file, just parse) |
| **Unknown properties** | Forward compatibility — unknown fields are preserved, not rejected |
| **Note node** | Note with text content — parsed, not rendered, preserved through round-trip |
| **Prompt node** | Prompt with content and `model` property — parsed, not rendered |
| **Context node** | Context with text content — parsed, extracted as semantic metadata for agent |
| **Context in hierarchy** | Context node nested inside a frame alongside visual nodes — verify it's associated with the right subtree and doesn't affect layout |
| **Multiple contexts** | Several context nodes at different levels — verify all extracted |
| **Realistic annotated template** | A lower-third design with context nodes like "call-to-action section" and "contrast with background" — verify the full structure survives parsing with annotations intact |

### 2. Variable Resolution Tests

These validate `PenVariableResolver`: given a tree with `$variable` bindings and a variables block, does it produce the correct resolved values?

| Test case | What it exercises |
|-----------|-------------------|
| **Simple binding** | `fill: "$primary"` → resolved to `"#FF0000"` |
| **Nested variable name** | `fill: "$color.primary"` with dotted variable key |
| **All value types** | Boolean, color, number, string variable resolution |
| **Unresolved variable** | `$nonexistent` — verify graceful handling (passthrough or default) |
| **Variable referencing variable** | `$a` resolves to `$b` which resolves to a value — chain resolution |
| **Theme resolution** | Variable with theme-conditional values, verify correct value wins per theme |
| **Multi-axis themes** | Two theme dimensions (e.g., mode × density), verify intersection logic |
| **Theme on node** | Node-level `theme` override, verify it scopes variable resolution to children |

### 3. Ref Expansion Tests

These validate `PenRefExpander`: given a tree with `ref` nodes pointing to `reusable` components, does it produce the correct expanded tree?

| Test case | What it exercises |
|-----------|-------------------|
| **Simple ref** | Ref → component with no overrides — verify full tree cloned |
| **Property override on root** | Ref overrides `fill` on the component root |
| **Descendant property override** | `descendants: { "label": { content: "Hello" } }` — single level |
| **Deep descendant override** | `descendants: { "card/header/label": { ... } }` — multi-level path |
| **Object replacement** | Descendant override with `type` present — whole subtree replaced |
| **Children replacement** | Descendant override with `children` array — children swapped |
| **Enabled=false deletion** | Descendant override `{ enabled: false }` — verify node suppressed |
| **Nested refs** | Ref inside a reusable component — verify recursive expansion |
| **Ref with variable overrides** | Instance that overrides variable-bound properties |

### 4. Layout Engine Tests (Ground truth from `snapshot_layout`)

These are the highest-value tests. Each test creates a .pen structure in Pencil, captures computed layout via `snapshot_layout`, and asserts our `PenLayoutEngine` produces identical rects.

| Test case | What it exercises |
|-----------|-------------------|
| **Absolute positioning** | `layout: "none"`, children at explicit x/y — verify positions |
| **Horizontal stack** | `layout: "horizontal"`, three fixed-width children — verify x positions |
| **Vertical stack** | `layout: "vertical"`, three fixed-height children — verify y positions |
| **Gap** | Horizontal stack with `gap: 16` — verify spacing between children |
| **Padding (uniform)** | Frame with `padding: 24` — verify children offset from edges |
| **Padding (2-value)** | `padding: [16, 24]` — horizontal vs. vertical |
| **Padding (4-value)** | `padding: [8, 16, 24, 32]` — all four sides different |
| **justifyContent: start** | Default — children packed to start of main axis |
| **justifyContent: center** | Children centered on main axis |
| **justifyContent: end** | Children packed to end of main axis |
| **justifyContent: space_between** | Children spread with equal space between |
| **justifyContent: space_around** | Children spread with equal space around each |
| **alignItems: start** | Children aligned to start of cross axis |
| **alignItems: center** | Children centered on cross axis |
| **alignItems: end** | Children aligned to end of cross axis |
| **fill_container** | Single child fills parent — verify matches parent minus padding |
| **Multiple fill_container** | Three fill_container children — verify equal split |
| **Mixed fixed + fill** | Two fixed children + one fill_container — verify fill gets remainder |
| **fit_content** | Parent sizes to children — verify parent width/height computed |
| **fit_content with fallback** | `fit_content(200)` with no children — verify fallback used |
| **fill_container with fallback** | `fill_container(300)` in non-layout parent — verify fallback used |
| **Nested layout** | Vertical frame containing horizontal frames — verify two-level layout |
| **Deep nesting** | 4+ levels of nested flex containers — verify recursive correctness |
| **Text auto sizing** | `textGrowth: "auto"` — verify text node sizes to content (single line) |
| **Text fixed-width** | `textGrowth: "fixed-width"` — verify wrapping and height calculation |
| **Text fixed-width-height** | Both dimensions fixed — verify no auto-sizing |
| **Text in flex container** | Text with `fill_container` width inside horizontal layout |
| **Corner case: all fill_container** | Parent is fit_content, all children are fill_container — circular dependency handling |
| **Corner case: zero children** | Empty frame with fit_content — verify fallback or zero |
| **Corner case: single child** | Verify justifyContent/alignItems with just one child |

### 5. Renderer Tests (Ground truth from `get_screenshot`)

These validate the visual output. Each test creates a .pen structure, captures Pencil's screenshot, and compares against our `PenRenderer` output. Due to font rendering and antialiasing differences, these use perceptual comparison (structural similarity) rather than pixel-exact matching.

| Test case | What it exercises |
|-----------|-------------------|
| **Solid fill rectangle** | Single color fill on a rectangle |
| **Multiple fills** | Layered fills (solid + gradient) on one shape |
| **Corner radius** | Rectangle with uniform corner radius |
| **Per-corner radius** | Four different corner radius values |
| **Linear gradient** | Gradient fill with rotation and multiple stops |
| **Radial gradient** | Radial gradient with center and size |
| **Angular gradient** | Angular/conic gradient |
| **Image fill** | Image fill with stretch/fill/fit modes |
| **Stroke: inside** | Stroke aligned inside |
| **Stroke: center** | Stroke aligned center |
| **Stroke: outside** | Stroke aligned outside |
| **Stroke: per-side thickness** | Different thickness on each side |
| **Stroke: dash pattern** | Dashed/dotted stroke |
| **Shadow: outer** | Drop shadow with offset, blur, spread, color |
| **Shadow: inner** | Inset shadow |
| **Blur** | Gaussian blur on a node |
| **Opacity** | Node at 50% opacity |
| **Rotation** | Node rotated 45° |
| **Clipping** | Frame with `clip: true`, children overflowing — verify clipped |
| **Blend modes** | At least: multiply, screen, overlay on layered elements |
| **Text: basic** | Simple text with font, size, weight, color |
| **Text: alignment** | All 3 horizontal × 3 vertical alignment combos |
| **Text: wrapping** | Long text in fixed-width — verify line breaks |
| **Text: rich spans** | Mixed bold/italic/colored spans in one text node |
| **Text: letter spacing** | Positive and negative letter spacing |
| **Text: line height** | Custom line height ratio |
| **Text: underline/strikethrough** | Decorations rendered correctly |
| **Ellipse** | Basic ellipse, plus inner radius (ring) and arc angles |
| **Path** | SVG path data with fill and stroke |
| **Polygon** | Regular polygon with corner count and radius |
| **Nested frames with fills** | Parent and child both have fills — verify paint order |
| **Component instance** | Ref rendering matches component with overrides applied |
| **Realistic: lower third** | Full lower-third title with text, background, layout |
| **Realistic: caption** | Word nodes in flex layout with variable fills |
| **Graceful degradation** | Mesh gradient node — verify renders without crashing (transparent or fallback color) |

### 6. Animation Tests

These don't need Pencil ground truth — they're pure math. We test against manually computed expected values.

| Test case | What it exercises |
|-----------|-------------------|
| **Linear interpolation** | Two keyframes, linear easing — verify midpoint |
| **Ease in/out/in-out** | Standard easing curves at various t values |
| **Cubic bezier** | Custom bezier curve — verify against known values |
| **Step (boolean)** | Boolean property — no interpolation, step at keyframe time |
| **Color interpolation** | RGBA component-wise lerp between two colors |
| **Hold before first keyframe** | Time before first keyframe — verify holds first value |
| **Hold after last keyframe** | Time after last keyframe — verify holds last value |
| **Single keyframe** | One keyframe only — verify constant value |
| **Many keyframes** | 10+ keyframes — verify correct segment selection |
| **Expression: simple** | `scene.t * 100` — verify evaluation |
| **Expression: scene access** | `scene.audio.amplitude` — verify context injection |
| **Expression: this reference** | `this.opacity * 0.5` — verify node property access |
| **Expression: overrides keyframe** | Keyframed value available via `this`, expression transforms it |
| **Expression: error handling** | Syntax error in expression — verify graceful failure, no crash |

### 7. Integration Tests

End-to-end tests that exercise the full pipeline: .pen file → parse → resolve → expand → animate → layout → render → CGImage.

| Test case | What it exercises |
|-----------|-------------------|
| **Static title** | .pen with variables, no animation — verify rendered output |
| **Animated title at t=0** | Title with keyframes, rendered at start — verify initial state |
| **Animated title at t=0.5** | Same title at midpoint — verify interpolated state |
| **Animated title at t=1** | Same title at end — verify final state |
| **Expression-driven title** | Title with expression binding — verify scene-reactive behavior |
| **Caption with word highlighting** | Caption overlay with transcript expression — verify correct word highlighted |

## Generation Plan

### Ordering

Build fixtures bottom-up, matching the implementation phases from the parent design doc:

1. **Parser fixtures** (Phase 1) — .pen JSON files covering all node types and structures. No Pencil rendering needed; these test parsing correctness.
2. **Variable + ref fixtures** (Phase 1) — .pen files with variables and refs, plus manually written expected resolved/expanded trees.
3. **Layout fixtures** (Phase 1) — .pen files created in Pencil via `batch_design`, layout captured via `snapshot_layout`. This is where the MCP oracle shines.
4. **Renderer fixtures** (Phase 2) — same .pen files, screenshots captured via `get_screenshot`. Visual reference PNGs.
5. **Animation fixtures** (Phase 3) — manually constructed keyframe/expression test data. No Pencil involvement.
6. **Integration fixtures** (Phase 4) — realistic .pen files with animation data, full-pipeline expected outputs.

### Fixture generation session

The layout and renderer fixtures require an interactive session with the Pencil MCP. The plan:

1. Open a blank .pen file in Pencil.
2. For each layout test case, use `batch_design` to create the structure, then `snapshot_layout` to capture computed rects, then `get_screenshot` for visual reference.
3. Use `batch_get` with full depth to export the final .pen JSON.
4. Save all three artifacts (JSON, layout, PNG) to the fixtures directory.
5. Clear the canvas and repeat for the next test case — or use `find_empty_space_on_canvas` to place each test case in its own area.

Each test case should be minimal — isolate one feature per fixture. A "horizontal stack with gap" fixture should contain *only* a horizontal frame with fixed-width children and a gap, nothing else. This makes failures diagnostic: if the test fails, we know exactly what's wrong.

### Naming convention

```
{category}-{feature}.pen           → e.g. layout-horizontal-gap.pen
{category}-{feature}.layout.json   → e.g. layout-horizontal-gap.layout.json
{category}-{feature}.png           → e.g. layout-horizontal-gap.png
```

Categories: `parser`, `variables`, `refs`, `layout`, `render`, `integration`.

## Validation Strategy

### Layout tests: exact match

```swift
// Assert computed rects match Pencil's snapshot_layout output exactly
let computed = PenLayoutEngine.layout(document)
let expected = loadLayoutFixture("layout-horizontal-gap")
for (nodeID, expectedRect) in expected {
    XCTAssertEqual(computed[nodeID], expectedRect, accuracy: 0.5)
    // 0.5px tolerance for floating point — tighten if possible
}
```

### Renderer tests: perceptual comparison

Pixel-exact comparison will fail due to font hinting, antialiasing, and subpixel rendering differences between Pencil (likely Skia or web-based) and our Core Graphics renderer. Options:

1. **Structural similarity (SSIM)** — compare overall structure with a threshold. Good for catching layout errors and color mismatches.
2. **Manual review** — generate our output, place it side-by-side with the Pencil reference, and eyeball it. Fine for initial development.
3. **Selective exact matching** — for tests without text (pure shapes, fills, gradients), pixel comparison may be close enough with a small tolerance.

Recommendation: start with manual review during development, add SSIM-based snapshot tests once the renderer is stable. Text-heavy tests always use perceptual comparison; shape-only tests can use tighter thresholds.

### Regression

Once the corpus is established, it becomes a regression suite. Any future changes to the parser, layout engine, or renderer must pass the full corpus. If a test starts failing, either our code regressed or Pencil changed their behavior (check by re-capturing from Pencil).

## Open Questions

- **Font availability:** Pencil may use web fonts or system fonts that differ from what Core Text has access to. We may need to normalize font names or bundle specific fonts for test fixtures. Consider using a single, universally available font (e.g., Helvetica, SF Pro) for all test fixtures.
- **Canvas size:** Do we render at a fixed size for all tests (e.g., 1920×1080) or let each fixture define its own viewport? Fixed size is simpler for comparison.
- **Pencil version pinning:** If Pencil updates their rendering, our reference PNGs become stale. We should record the Pencil version used to generate each fixture batch.
- **CI integration:** Screenshots require Pencil MCP, which requires the desktop app. Layout JSON and parser tests can run headlessly. Renderer snapshot tests may need to be a local-only validation step initially.
