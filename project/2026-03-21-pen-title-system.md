# Pen-Based Title System

**Date:** 2026-03-21
**Status:** Draft — pending review

## Why

FPP's current title system uses JavaScript Canvas 2D templates executed via JavaScriptCore. This is powerful — templates are Turing-complete and can express procedural animation, data-driven graphics, and reactive behavior. But it has a fundamental limitation: the output is opaque. Users can adjust parameters, but they can't directly manipulate layers, tweak individual word timing, or edit layout without modifying code.

We want a title system where:

1. **Agents generate titles that users can edit** — not just parameter sliders, but direct manipulation of layers, keyframes, and layout.
2. **Layout is declarative** — flexbox-style "stack these, center them, 16px gap" rather than imperative pixel math.
3. **Animation is inspectable** — keyframes visible in the timeline, individually adjustable.
4. **The format is interchangeable** — titles can round-trip with an external design tool.

The [Pencil](https://pencil.dev) `.pen` format meets these requirements. It's a JSON scene graph with flexbox layout, variables, and a component/instance system — designed from the ground up for LLM authoring. By adopting `.pen` as our title design format and building our own rendering and animation layers, we get a proven, token-efficient format with design tool interchange, without coupling to Pencil's runtime.

## Terminology

| Term | Definition |
|------|-----------|
| **.pen file** | JSON document describing a visual scene graph (Pencil's format) |
| **Node** | A single element in the scene graph (frame, text, rectangle, etc.) |
| **Variable** | A named, typed value in a .pen file that can be bound to node properties via `$name` |
| **Ref / Instance** | A node that replicates a reusable component, with optional property overrides |
| **Keyframe track** | A time-indexed sequence of values for a single animatable property on a single node |
| **Expression** | A JavaScript snippet that computes a property value at render time, with access to scene state |
| **Title** | The FPP-level concept: a .pen design + animation data (keyframes/expressions), placed on the timeline |
| **PenRenderer** | Our Core Graphics-backed renderer that rasterizes a .pen scene graph to a CGImage |

## Architecture Overview

The system has four layers, each with a clear responsibility:

```
┌─────────────────────────────────────────────────────┐
│  .pen scene graph                                   │  ← What it looks like
│  (static design: layout, typography, color, shape)  │     Authored in Pencil or by agent
├─────────────────────────────────────────────────────┤
│  Keyframe tracks                                    │  ← How it moves
│  (per-node, per-property, time-indexed values)      │     Editable in timeline UI
├─────────────────────────────────────────────────────┤
│  Expressions (optional)                             │  ← Reactive/procedural behavior
│  (JS snippets with access to scene state)           │     Power-user escape hatch
├─────────────────────────────────────────────────────┤
│  PenRenderer                                        │  ← Rasterization
│  (Core Graphics-backed, HDR-aware compositor)       │     Produces CGImage per frame
└─────────────────────────────────────────────────────┘
```

### Design decisions captured

- **Keyframes over imperative animation.** The current JS system conflates layout, drawing, and animation in imperative code. Separating design (scene graph) from motion (keyframes) makes titles fundamentally more editable.
- **Expressions as escape hatch, not primary system.** Most animation is keyframes. Expressions exist for cases where properties must react to runtime state (audio amplitude, transcript position). This is the After Effects model: keyframes for 95% of work, expressions for the rest.
- **.pen files are sRGB, rendering is HDR-aware.** The .pen format uses hex colors (`#RRGGBB` / `#RRGGBBAA`), which are sRGB. This preserves interchange with Pencil. HDR brightness is handled at the rendering/compositing boundary (see [HDR Brightness](#hdr-brightness)).
- **Animation data lives outside the .pen file.** Keyframes and expressions are stored in `project.json`, not in the .pen file. This preserves clean round-tripping — a .pen file can be opened in Pencil, edited, and dropped back in without losing or corrupting animation data.
- **This replaces the JS Canvas 2D system.** The existing graphics engine (CanvasBridge, GraphicsRuntime, FPPStandardLibrary, etc.) will be extracted to TCC or a standalone package for reuse in other contexts. FPP's title system will use PenRenderer exclusively.

## The .pen Format — What We Support

The .pen format is documented at [docs.pencil.dev](https://docs.pencil.dev/for-developers/the-pen-format). It is a JSON scene graph with the following capabilities. We support a subset, documented here.

> **Note:** The .pen format spec is marked as subject to breaking changes. We should version-pin our parser and treat .pen import as a well-defined boundary. If the format evolves, we update our parser explicitly rather than tracking HEAD.

### Supported node types

| Node type | Notes |
|-----------|-------|
| `frame` | Primary container. Flexbox layout, fills, strokes, effects, corner radius, clip. |
| `rectangle` | Positioned shape with optional corner radius. |
| `ellipse` | Bounding-box defined. Inner radius, arc angles. |
| `text` | Rich text with font, size, weight, alignment, line height, textGrowth modes. |
| `path` | SVG path geometry with fill rules. |
| `group` | Effectless container with optional layout. |
| `ref` | Component instance with descendant overrides. |
| `line` | Simple stroke element. |
| `polygon` | Regular polygon with configurable corner count. |

### Supported features

| Feature | Scope |
|---------|-------|
| **Flexbox layout** | `layout` (none/vertical/horizontal), `gap`, `padding`, `justifyContent`, `alignItems`. Single-axis only, no wrapping. |
| **Sizing** | Fixed numbers, `fit_content`, `fill_container`, with fallback values. |
| **Fills** | Solid color, linear gradient, radial gradient, angular gradient, image fill. |
| **Strokes** | Align, thickness (uniform and per-side), join, cap, dash pattern. |
| **Effects** | Shadow (inner/outer), blur. |
| **Text** | fontFamily, fontSize, fontWeight, fontStyle, letterSpacing, lineHeight, textAlign, textAlignVertical, textGrowth (auto/fixed-width/fixed-width-height), rich text spans. |
| **Variables** | Typed (boolean, color, number, string) with `$name` binding. Theme-aware values. |
| **Themes** | Multi-axis theme dimensions with variable value resolution. |
| **Components** | `reusable: true` marks components; `ref` nodes instantiate them with descendant overrides (property override, object replacement, children replacement). |
| **Transforms** | Position (x, y), rotation, opacity, flipX, flipY. |
| **Clipping** | Frame `clip` property. |
| **Blend modes** | Full set (normal, multiply, screen, overlay, etc.). |
| **Imports** | Cross-file variable and component references. |

### Deferred / unsupported

| Feature | Reason |
|---------|--------|
| **Mesh gradients** | Complex bezier-interpolated color grids. Low priority for titles. Can be added later if demand arises. |
| **Background blur** | Requires compositing awareness of content behind the title layer. Possible future addition. |
| **Icon fonts** | Lucide, Material Symbols, etc. Would require bundling font files. Could support a subset later; for now, agents can use SVG paths. |
| **Note / Prompt / Context** | Pencil-specific annotation types. Not rendered visually. However, `context` nodes carry designer intent ("this is a call-to-action section," "these colors should contrast with the background") that our agent should parse and use when modifying titles. Preserve these nodes through round-trips; surface them to the agent as semantic metadata. |

## Data Model

### Storage layout

```
MyProject.fpp/
├── project.json              ← Timeline, tracks, overlays (incl. animation data per overlay)
├── graphics/
│   ├── lower-third.pen       ← Openable in Pencil
│   ├── end-card.pen
│   └── assets/
│       └── logo.png          ← Referenced by image fills in .pen files
├── graphics.json             ← GraphicInstance store (migration period — see Migration)
├── agent-conversations.json
└── ...
```

The `graphics/` subfolder contains .pen files that are fully portable — a user can open them in Pencil, edit the design, and drop them back. Animation data (keyframes, expressions) lives in `project.json` as part of the overlay definition.

### Title data model

A **title** in FPP is an overlay on the timeline that references a .pen file and carries animation data:

```swift
/// A placed title on the timeline. Stored as part of the overlay in project.json.
struct TitleInstance: Friendly, Identifiable {
    let id: String                                  // UUID
    let penFilePath: String                         // Relative path within .fpp bundle (e.g. "graphics/lower-third.pen")
    var variableOverrides: [String: ParamValue]     // Bound variable values (maps to .pen $variables)
    var keyframeTracks: [KeyframeTrack]              // Per-node, per-property animation
    var expressions: [ExpressionBinding]            // Optional JS expressions
    var brightnessOverride: Double?                 // Per-title HDR brightness (nil = use timeline default)
}
```

```swift
/// A keyframe track animates a single property on a single node over time.
struct KeyframeTrack: Friendly {
    let nodeID: String                              // .pen node id (or id path for nested: "card/label")
    let property: String                            // Animatable property name (e.g. "opacity", "x", "fill")
    var keyframes: [Keyframe]                       // Time-sorted
}

struct Keyframe: Friendly {
    let time: Rational                              // Relative to overlay start
    let value: ParamValue                           // Property value at this time
    var easing: EasingCurve                         // Interpolation to next keyframe
}

enum EasingCurve: Friendly {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case cubicBezier(cp1x: Double, cp1y: Double, cp2x: Double, cp2y: Double)
}
```

```swift
/// An expression overrides (or augments) a property with a JS snippet evaluated per frame.
struct ExpressionBinding: Friendly {
    let nodeID: String                              // .pen node id or id path
    let property: String                            // Property to drive
    let source: String                              // JavaScript expression source
    var enabled: Bool                               // Can be toggled off without deleting
}
```

### Animatable properties

Not every .pen property needs to be animatable. The initial set:

| Property | Value type | Interpolation |
|----------|-----------|---------------|
| `x`, `y` | Number | Linear / eased |
| `width`, `height` | Number | Linear / eased |
| `opacity` | Number (0–1) | Linear / eased |
| `rotation` | Number (degrees) | Linear / eased |
| `fill` (solid color) | Color | Component-wise RGBA lerp |
| `fontSize` | Number | Linear / eased |
| `cornerRadius` | Number | Linear / eased |
| `gap`, `padding` | Number | Linear / eased |
| `stroke.thickness` | Number | Linear / eased |
| `effect.shadow.blur` | Number | Linear / eased |
| `effect.shadow.offset` | Point | Linear / eased |
| `effect.shadow.color` | Color | Component-wise RGBA lerp |
| `effect.blur.radius` | Number | Linear / eased |
| `letterSpacing` | Number | Linear / eased |
| `enabled` | Boolean | Step (no interpolation) |

Gradient stops, text content, and structural properties (layout, alignItems, etc.) are not interpolated — they can be changed via step keyframes or expressions.

### Overlay integration

The existing `Overlay` type in TCC references content by `referenceID`. Currently this points to a `GraphicInstance.id`. In the new system, it points to a `TitleInstance.id`. The `Overlay` struct itself doesn't change — the semantics of `referenceID` expand.

```
Timeline → Track (.overlay) → Overlay → referenceID → TitleInstance → .pen file + animation
```

## Layout Engine

The .pen layout system is **not** full CSS flexbox. It is single-axis stack layout with alignment and distribution. From the Pencil docs:

> "Flexbox layout is single-axis only with no item wrapping."

### Supported layout properties

- `layout`: `"none"` (absolute positioning) | `"vertical"` | `"horizontal"`
- `gap`: uniform spacing between children on main axis
- `padding`: 1 value (all sides), 2 values (h, v), or 4 values (t, r, b, l)
- `justifyContent`: `start` | `center` | `end` | `space_between` | `space_around`
- `alignItems`: `start` | `center` | `end`
- Sizing: fixed number | `fit_content` | `fill_container` (with optional fallback)

### Layout algorithm

The layout engine is a recursive, two-pass algorithm:

**Pass 1 — Measure (bottom-up):**
1. Leaf nodes report their intrinsic size (fixed number, or text measurement for auto-growth text).
2. `fit_content` containers sum their children's sizes + gaps + padding.
3. `fill_container` nodes are deferred (need parent size).

**Pass 2 — Arrange (top-down):**
1. Parent computes available space (own size minus padding).
2. Subtract fixed-size and fit_content children + gaps.
3. Divide remaining space equally among `fill_container` children.
4. Position children along main axis per `justifyContent`.
5. Align each child along cross axis per `alignItems`.
6. For `layout: "none"`, children use their `x`/`y` coordinates relative to parent.

This is a bounded, well-defined algorithm — no iterative constraint solving. Implementable in a few hundred lines of Swift.

### Text measurement

Text nodes with `textGrowth: "auto"` are measured as single-line text (no wrapping). `fixed-width` wraps to the node's width and reports measured height. `fixed-width-height` uses both dimensions as-is. Text measurement uses Core Text (`CTFramesetter`) for accurate metrics.

## PenRenderer

The renderer takes a resolved scene graph (after layout, variable substitution, keyframe/expression evaluation) and produces a `CGImage`.

### Pipeline

```
.pen JSON
  → Parse (PenParser: JSON → PenDocument)
  → Resolve variables (substitute $bindings, apply theme)
  → Expand refs (inline component instances with overrides)
  → Apply animation (evaluate keyframes + expressions at current time)
  → Layout (two-pass measure/arrange)
  → Render (Core Graphics draw calls → CGImage)
```

### Rendering approach

Like the existing CanvasBridge, PenRenderer uses a float-precision `CGContext` for HDR/wide-gamut support. The rendering walk is a recursive tree traversal:

1. For each node, push CG state (`saveGState`).
2. Apply transform (translate to position, rotate, apply opacity).
3. If frame with `clip`, set clipping path.
4. Draw fills (solid → `setFillColor` + `fill`; gradient → `drawLinearGradient`/`drawRadialGradient`; image → `draw(_:in:)`).
5. Draw stroke if present.
6. For text nodes, use Core Text to render styled text.
7. For path nodes, parse SVG path data and stroke/fill the `CGPath`.
8. Apply effects (shadow via `setShadow`; blur via CIFilter post-process or pre-render to image + blur).
9. Recurse into children.
10. Pop CG state (`restoreGState`).

### Nonisolated design

Like `CanvasBridge`, `PenRenderer` is `final nonisolated class` — it opts out of the module's default `@MainActor` isolation so rendering can happen on background threads. The coordinator dispatches rendering off the main actor to avoid UI stalls.

## HDR Brightness

### Problem

.pen files use sRGB hex colors. A white title (`#FFFFFF`) maps to 1.0 in linear light, which looks correct on an SDR display but appears dim against HDR video content (where highlights can be many times brighter).

### Solution

Brightness is applied at the compositing boundary, not in the .pen file:

1. **Timeline-level title brightness** — A gain/nits setting applied to all titles by default. For example, "SDR titles at 203 nits" for HLG content, or a user-tunable value. This maps sRGB 1.0 white to the target brightness in the output color space.

2. **Per-overlay brightness override** — Each `TitleInstance` can override the timeline default (e.g., +1 stop, or an absolute value). This allows punching individual titles brighter or pulling them back.

3. **The .pen file is unmodified** — sRGB colors stay sRGB. The brightness mapping happens in PenRenderer's final compositing step, after rasterization. This preserves round-tripping with Pencil.

### Implementation

After PenRenderer produces a CGImage in sRGB, the compositor applies a brightness transform before blending onto the video frame. This is the same pattern used in broadcast graphics — titles are authored in a standard color space and gain-mapped to the output.

## Expressions

### Runtime

Expressions reuse FPP's existing JavaScriptCore infrastructure. Each expression is a lightweight JS snippet (not a full template) evaluated per frame. The expression context provides:

```javascript
// Available in all expressions:
scene.time          // Current time in seconds (within overlay duration)
scene.t             // Normalized time 0...1 (within overlay duration)
scene.frame         // Current frame number
scene.duration      // Overlay duration in seconds
scene.viewport      // { width, height }

// Audio
scene.audio.amplitude   // RMS amplitude at current frame (0...1)

// Transcript (when clip has transcription)
scene.transcript.words          // Array of { text, start, end }
scene.transcript.currentWord    // Word object active at current time, or null
scene.transcript.isActiveWord(name)  // Helper: true if word matching name is active

// Node context
this.name           // Current node's name
this.id             // Current node's id
this[property]      // Current keyframed value of any property (before expression override)

// Utility
lerp(a, b, t)
clamp(value, min, max)
easeInOut(t)        // ...and other easing functions
```

### Expression evaluation order

1. Resolve .pen variables (static)
2. Evaluate keyframes at current time (interpolated values)
3. Evaluate expressions (can read keyframed values via `this[property]`, can override them)

This means expressions compose with keyframes: a keyframe can provide a base value that an expression modifies. For example, a keyframed `y` position with an expression that adds `Math.sin(scene.time * 2) * 5` for subtle oscillation.

### Performance

Expressions are evaluated per-node-per-property-per-frame. For a title with 20 nodes and 2 expressions, that's 2 JS evaluations per frame — trivial compared to the current system which runs an entire Canvas 2D render pipeline in JS. The JSContext can be cached per title instance (same pattern as current `GraphicsRuntime` caching in `GraphicsCoordinator`).

## Caption System

### Motivation

Captions are an unusually repetitive title task: the same visual template applied to every phrase in a transcript, potentially hundreds of times. While the general title workflow (agent generates .pen + keyframes) works, it would be inefficient for an agent to manually place hundreds of individual overlays.

### Approach

A **caption tool** generates caption overlays in batch from a transcript and a caption style:

1. Agent (or user) selects a caption style (a .pen template designed for captions).
2. Agent calls the caption tool with a time range and the template.
3. The tool reads the transcript for that range, segments it into phrases/sentences.
4. For each phrase, it generates a `TitleInstance` with:
   - Word nodes populated from the transcript
   - Keyframes for entrance/exit animation (from the style)
   - Expression on word fill for highlight timing: `scene.transcript.isActiveWord(this.name) ? '$highlight' : '$text'`
5. It places overlays on the timeline, auto-stacking on the caption track.

The result is a set of concrete, editable caption overlays. The user can then adjust individual captions — change a word's font, nudge timing, modify the highlight color — because each caption is a fully materialized title, not an opaque JS function.

### Tradeoff vs. current system

The current JS system can handle captions as a single layer across the entire timeline, which is more elegant. The .pen approach produces more objects but each is individually editable. The gain is that creative variation becomes possible: different styles for different speakers, emphasis on key words, per-caption layout adjustments.

## Template Library

### Template structure

A title template is a .pen file with:

- **Variables** defining the editable parameters (`$speaker.name`, `$accent.color`, etc.)
- **Reusable components** for structural elements
- **A top-level frame** representing the title viewport

Templates live in two locations (same pattern as current system):

- **Built-in:** `Bundle.main/Resources/Templates/` (immutable, ships with app)
- **User:** `~/Library/Application Support/FirstPassPro/Templates/` (user-managed, file-watched)

### Template metadata

The current `GraphicSchema` (name, description, category, tags, params) maps naturally to the .pen system:

- `name`, `description`, `category`, `tags`, `author` → stored as metadata in the .pen file (using Pencil's `context` or `note` nodes, or a convention like a top-level `metadata` property — TBD).
- `params` → derived from the .pen file's `variables` block. Each variable becomes a parameter in the inspector.
- `defaultDuration` → stored alongside the template reference (not in the .pen file itself, since duration is a timeline concept).

### Animation presets

Templates can bundle default keyframe tracks and expressions. When a template is placed on the timeline, its preset animation is applied. The user can then modify or replace the keyframes.

This is stored as a sidecar JSON file (e.g., `lower-third.animation.json`) alongside the .pen file in the template directory. The sidecar contains `KeyframeTrack` and `ExpressionBinding` arrays referencing node IDs in the .pen file.

```
Templates/
├── Lower Thirds/
│   ├── Minimal.pen
│   ├── Minimal.animation.json
│   ├── Bold.pen
│   └── Bold.animation.json
```

## Editing Model

The core promise of this system is that **agents generate titles that users can edit**. This section describes the interaction model — how users see, select, and manipulate title elements in the preview and inspector.

### Selection model

Selection operates at two levels:

1. **Overlay selection** — clicking a title overlay in the timeline (or clicking the title in the preview) selects the overlay. This is the existing behavior, showing the title's bounding box and populating the inspector with top-level properties (variables, brightness, duration).

2. **Node selection** — double-clicking an overlay (or expanding it in the inspector) enters **node editing mode**, where individual .pen nodes become selectable. Clicking a text node, a frame, or a shape in the preview selects that node and shows its properties in the inspector.

This is analogous to Figma's "click to select group, double-click to enter group" pattern, or After Effects' "select layer vs. enter precomp."

The current selection enum (`.graphicInstance(overlayID)`) extends to something like:

```swift
enum Selection: Friendly {
    // ...existing cases...
    case title(overlayID: String)                           // Overlay selected
    case titleNode(overlayID: String, nodeIDPath: String)   // Node within title selected
}
```

### Preview overlay

When a title is selected, the preview shows:

- **Bounding box** — the title's overall frame, with drag handles for repositioning the overlay.
- **Node outlines** — when in node editing mode, each node's computed layout rect is shown as a thin outline (like Figma's selection rectangles). The selected node gets a highlighted border with handles.

When a node is selected:

- **Frames/rectangles** — resize handles on corners and edges.
- **Text nodes** — double-click enters text editing mode (direct inline editing of content).
- **Any node** — drag to reposition (inserts a keyframe at the current playhead position if animation is active, or modifies the static property if not).

### Hit testing

The current `GraphicsHitTester` uses pixel-alpha testing (re-render and check alpha at click point). The .pen system enables **node-tree hit testing**: after layout, every node has a computed rect. Hit testing walks the tree front-to-back (last child first, for z-order) and returns the deepest node whose rect contains the click point. This is faster and more precise than pixel-alpha, and it correctly hits transparent frames that serve as layout containers.

For nodes with rotation or complex paths, we transform the hit point into the node's local coordinate space before testing.

### Inspector

The inspector adapts based on selection level:

**Overlay selected (title-level):**
- Variable overrides (derived from .pen `variables` — text fields, color pickers, number sliders)
- Brightness override
- Duration
- Animation summary (number of keyframe tracks, expressions)

**Node selected (node-level):**
- Node-type-specific properties (fill, stroke, font, corner radius, etc.)
- Layout properties (if the node is a frame: layout direction, gap, padding, alignment)
- Transform (position, rotation, opacity)
- Keyframes for this node (list of animated properties with keyframe markers)
- Expression bindings (if any, with enable/disable toggle and source editor)

### Direct manipulation → keyframe interaction

A key UX question: when the user drags a node in the preview, does it modify the static .pen property or insert a keyframe?

Proposed behavior:
- **No animation exists for this property:** Modifying it changes the .pen node's static value. This is the "design" workflow.
- **Keyframes exist for this property:** Modifying it inserts (or updates) a keyframe at the current playhead time. This is the "animate" workflow.
- **An expression drives this property:** The property is shown as read-only in the preview (with a visual indicator like an `=` badge). The user must disable or edit the expression to regain direct control.

This mirrors After Effects' behavior: editing a property with keyframes adds a keyframe at the current time; editing without keyframes changes the static value.

### Node tree browser

For complex titles with deep nesting, a collapsible node tree (like Figma's layers panel) provides structural navigation. This could live in the inspector sidebar or as a disclosure section within the title inspector. Each row shows:

- Node type icon (frame, text, rectangle, etc.)
- Node name (from .pen `name` property, or auto-generated like "Text 1")
- Visibility toggle (maps to `enabled`)
- Keyframe indicator (dot if the node has any animated properties)

Clicking a row selects that node in the preview and scrolls the inspector to its properties.

## Integration with Existing Systems

### What carries over unchanged

| Component | Status |
|-----------|--------|
| `Overlay` (TCC) | Unchanged. `referenceID` points to `TitleInstance.id`. |
| `Track` / `TrackItem` (TCC) | Unchanged. Overlay tracks work as-is. |
| `GraphicsCoordinator` | Refactored: swap JS renderer cache for PenRenderer cache. Same coordination pattern (backpressure, CALayer update, hit testing). |
| `GraphicsFrameProcessor` | Refactored: use PenRenderer instead of GraphicsRuntime for export compositing. Same FrameProcessor callback pattern. |
| `SceneDataResolver` | Extended: same pure function, expanded to provide scene data for expression evaluation. |
| `AudioAmplitudeExtractor` | Unchanged. Feeds `scene.audio.amplitude`. |
| `ExportCoordinator` / `ExportSheetView` | Unchanged. |
| Timeline UI (TrackView, overlay rendering) | Refactored: render title overlays instead of graphic instance overlays. Same selection model. |
| `GraphicsOverlayView` | Refactored: display PenRenderer output instead of CanvasBridge output. |
| `GraphicsHitTester` | Likely rewritten to use PenRenderer's node tree for hit testing rather than pixel-alpha. |

### What's new

| Component | Purpose |
|-----------|---------|
| `PenParser` | JSON → `PenDocument` (typed Swift model of the .pen scene graph) |
| `PenLayoutEngine` | Two-pass flexbox layout (measure + arrange) |
| `PenRenderer` | `PenDocument` → `CGImage` via Core Graphics |
| `PenVariableResolver` | Substitute `$variable` bindings, apply themes |
| `PenRefExpander` | Inline `ref` nodes with descendant overrides |
| `TitleInstance` | Data model replacing `GraphicInstance` |
| `KeyframeEvaluator` | Interpolate keyframe tracks at a given time |
| `ExpressionEvaluator` | JSCore-backed per-property expression evaluation |
| `TitleInspectorView` | Parameter controls for title variables + keyframe editing |
| `CaptionTool` | Batch caption overlay generation from transcript |

### What's removed from FPP

The following move out of FPP (to TCC or a standalone package — destination TBD):

- `CanvasBridge` and all extensions
- `CanvasState`, `CanvasGradient`, `CanvasFontParser`
- `GraphicsRuntime`, `GraphicsRenderer`
- `FPPStandardLibrary`, `SourcePreprocessor`
- `SceneBuilder`
- `ParamValue+JSAny` (JS template-specific bridging)
- `TemplateThumbnailGenerator` (replaced by PenRenderer-based thumbnails)

These form a coherent Canvas 2D → CGImage rendering library that's valuable for other projects (CLI graphics, thumbnail generation, etc.) but no longer needed in FPP.

## Migration Notes

These are decisions and context from the initial design discussion that a fresh implementer should know:

1. **The .pen layout is NOT full CSS flexbox.** It's single-axis, no wrapping. Don't reach for Yoga or a full flexbox library — the layout algorithm is a few hundred lines of Swift. See [Layout Engine](#layout-engine).

2. **Mesh gradients are explicitly out of scope.** If a .pen file contains a mesh gradient, the renderer should degrade gracefully (e.g., render as transparent or use the first color). Don't block on implementing them.

3. **The .pen format may introduce breaking changes.** Version-pin the parser. Treat .pen files as external input with validation, not trusted internal data.

4. **Expressions share the JSCore runtime with the old system** but are architecturally different. The old system runs a full Canvas 2D pipeline per frame. Expressions are lightweight property evaluations. The JSContext caching pattern from `GraphicsCoordinator.CachedRenderer` applies, but the context setup is much simpler.

5. **The existing overlay/track model doesn't need to change.** `Overlay.referenceID` already abstracts over what it points to. The change is in what's stored at the other end of that reference.

6. **HDR is a compositing concern, not a format concern.** Don't try to extend .pen colors for HDR. Apply brightness gain after rasterization. See [HDR Brightness](#hdr-brightness).

7. **Pre-baking vs. expressions for scene-aware behavior:** For cases where scene data is known at placement time (transcript words, clip metadata), prefer generating concrete nodes and keyframes. Expressions are for truly dynamic behavior (audio reactivity, runtime-computed values). Pre-baked titles are more editable.

8. **The `GraphicInstance` model is heavier than needed for .pen titles.** It embeds the full JS source of the template. `TitleInstance` references a .pen file by path instead. During migration, both types may coexist briefly, but the goal is full replacement.

9. **CSSColorParser and CGColor+CSSString are reusable.** The .pen format uses hex colors, which our existing CSS color parser handles. These utilities stay in FPP (or move with the renderer).

10. **The current TemplateLibrary scans for JS files.** It will need to scan for .pen files instead (or in addition, during transition). The file-watching infrastructure (`TemplateFileWatcher`) carries over as-is.

## Implementation Phases

> Phase breakdown is preliminary. Refine during implementation planning.

### Phase 1: Parser and Layout Engine
- `PenParser`: JSON → `PenDocument` Swift model
- `PenVariableResolver`: `$variable` substitution
- `PenRefExpander`: component instance expansion
- `PenLayoutEngine`: two-pass measure/arrange
- **Exit criteria:** Can parse the Pencil format spec examples, resolve variables, expand refs, compute layout rects. Comprehensive unit tests.

### Phase 2: Renderer
- `PenRenderer`: resolved scene graph → CGImage via Core Graphics
- Fills (solid, linear/radial/angular gradient, image)
- Strokes, effects (shadow, blur)
- Text rendering via Core Text
- Path rendering (SVG path data → CGPath)
- HDR brightness mapping
- **Exit criteria:** Can render a representative set of .pen files to correct-looking CGImages. Visual snapshot tests.

### Phase 3: Animation System
- `KeyframeTrack`, `Keyframe`, `EasingCurve` data model
- `KeyframeEvaluator`: interpolate values at a given time
- `ExpressionEvaluator`: JSCore-backed property evaluation
- `TitleInstance` data model
- Animation sidecar format (`.animation.json`)
- **Exit criteria:** Can animate .pen node properties over time with keyframes and expressions. Unit tests for interpolation and expression evaluation.

### Phase 4: Integration
- Refactor `GraphicsCoordinator` to use PenRenderer
- Refactor `GraphicsFrameProcessor` for export
- Update overlay/track wiring
- Update document storage (graphics/ subfolder, project.json animation data)
- Template library scanning for .pen files
- **Exit criteria:** Titles render in preview and export. End-to-end from .pen file to rendered video frame.

### Phase 5: UI
- Title inspector (variable editing, keyframe display)
- Template browser for .pen templates
- Timeline keyframe visualization
- Caption tool (batch generation from transcript)
- **Exit criteria:** Users can browse templates, place titles, edit parameters, view/edit keyframes.

### Phase 6: Extraction
- Move Canvas 2D engine out of FPP (to TCC or standalone package)
- Remove JS template support from FPP
- Clean up dead code
- **Exit criteria:** FPP builds and all tests pass with no JS template code remaining.

## Open Questions

- **Template metadata convention:** How do we store name/description/category/tags in or alongside .pen files? A `metadata` node? A sidecar `.meta.json`? A convention using Pencil's `context` nodes?
- **Keyframe UI:** What does the timeline keyframe editor look like? Diamond markers on the overlay? A dedicated keyframe editor panel? This is a significant UI design question.
- **Expression editor:** Inline text field per property? A code editor panel? Error display?
- **Undo granularity:** Keyframe edits, variable changes, and expression edits all need undo support. What's the undo grouping?
- **Canvas 2D engine destination:** TCC? Standalone Swift package? TCC importing a standalone package? Decide during Phase 6.

## References

- [Pencil .pen format documentation](https://docs.pencil.dev/for-developers/the-pen-format)
- [Pencil CLI documentation](https://docs.pencil.dev/for-developers/pencil-cli)
- Existing graphics engine design: `project/2026-03-05-generator-design.md`
- Existing architecture: `FirstPassPro/Documentation.docc/Architecture.md`
