# CG Renderer: Background Blur Effect

**Date:** 2026-04-15
**Status:** Draft — awaiting approval
**Target:** `Sources/Woodcase/Rendering/PenRenderer.swift`, `Sources/Woodcase/Rendering/PenEffectRenderer.swift`

## Goal

Implement `PenEffect.backgroundBlur` in the CoreGraphics renderer. Semantics (confirmed with user):

- Samples whatever has already been drawn behind the node (the "backdrop").
- Applies a full-resolution Gaussian blur.
- Clips the blurred result to the node's own shape (rounded rect, path, etc.).
- Composites the blurred backdrop *under* the node's own fills/strokes/content.

Performance target: full-resolution, real Gaussian — no downsample tricks. CoreImage (`CIGaussianBlur`) is approved.

## Current State

The model side is already done:

- `PenEffect.backgroundBlur(PenBackgroundBlurEffect)` at `Sources/Woodcase/Models/PenEffect.swift:16`.
- `PenBackgroundBlurEffect { enabled, radius }` at `Sources/Woodcase/Models/PenEffect.swift:32`.
- Parsed from `"background_blur"` discriminator; handled by the variable resolver and React emitter.
- **Not** handled by the CG renderer — it's silently ignored today.

The CG renderer is a single-`CGContext` iterative walker (`PenRenderer.renderNodesIteratively` in `PenRenderer.swift:190`), driven by a `WorkItem` stack. Existing foreground-blur (`PenEffectRenderer.renderBlur`, `PenEffectRenderer.swift:181`) renders the node's *own* subtree into an offscreen context, blurs it, composites it back — that pattern is **not** what we want here, because background blur must capture pixels the renderer has *already* produced for other nodes.

## Design Options Considered

**Option A — Framebuffer readback via `CGContext.makeImage()`.** At the moment we're about to draw a background-blur node, call `makeImage()` on the main bitmap context to snapshot the current pixel state, crop to the node's rect (padded for kernel overflow), run `CIGaussianBlur` with `CIAffineClamp` edge handling, and draw the blurred `CGImage` back into the main context clipped to the node shape. Works only when the main context is bitmap-backed.

**Option B — Two-pass deferred rendering.** Build a command list during traversal, execute in a second pass with explicit offscreen targets per blur node. Mirrors RapidPro's Metal command-stream approach. Clean, but a significant architectural change to the CG renderer — it currently draws eagerly inline.

**Option C — Per-subtree offscreen recursion.** When we hit a background-blur node, back up to the nearest snapshot point, render everything-behind into a fresh offscreen, blur, then continue. Quadratic in the worst case and awkward to implement inside the iterative walker.

### Recommendation — Option A

Reasons:

1. The primary CG render entry point (`PenRenderer.render(_:layoutRects:size:...)` at `PenRenderer.swift:38`) creates a bitmap context we fully control. `makeImage()` is cheap on a bitmap context — it snapshots the current pixel buffer.
2. Matches the existing eager-render model. No architectural rework.
3. The only thing RapidPro does that we need (ordering: capture backdrop → blur → composite → draw node) falls out naturally from `processNode`'s existing ordering.
4. CoreImage already used for foreground blur — no new dependency.

Option B is the "correct" long-term answer if we ever need background blur on non-bitmap contexts (PDF export, window contexts, etc.), but we can document that limitation for v1 and revisit if it matters.

## Implementation Plan

### 1. New helper in `PenEffectRenderer.swift`

```swift
static func renderBackgroundBlur(
    _ effect: PenEffect.PenBackgroundBlurEffect,
    rect: PenRect,           // node's draw rect in current CTM (post-translate)
    clipPath: CGPath,        // the node's shape, in current CTM
    in context: CGContext
)
```

Logic:

1. Guard `enabled != false` and `radius > 0`; otherwise no-op.
2. Compute the capture region in **device pixels**:
   - Transform `clipPath.boundingBox` (or `rect`) by the current CTM to get device-space bounds.
   - Pad by `ceil(radius * scale * 3)` on all sides (kernel-radius rule-of-thumb used by `renderBlur`).
   - Intersect with the context's full pixel bounds.
   - If empty (node fully offscreen), no-op.
3. Call `context.makeImage()` → full-resolution `CGImage` of the current framebuffer. **Fail gracefully if nil** (non-bitmap context) — log via the renderer's existing diagnostic path and no-op.
4. Crop the `CGImage` to the padded capture region using `CGImage.cropping(to:)`.
5. Build a `CIImage` from the crop, wrap with `CIAffineClamp` (so the blur samples edge pixels rather than transparent fringe), apply `CIGaussianBlur` with the approved radius, then crop the output extent back to the original crop rect to discard the clamp halo.
6. Render to a `CGImage` via a shared `CIContext` (see note on caching below).
7. Draw the blurred image back into the main context, clipped to `clipPath`:
   - `saveGState`; `addPath(clipPath); clip()`; draw the `CGImage` at the rect matching the un-padded capture region (in the main context's local coordinate space); `restoreGState`.
   - Coordinate care: `CGContext.draw(_:in:)` uses bottom-left origin semantics, so we follow the same un-flip-then-draw dance used at the bottom of `renderBlur` (`PenEffectRenderer.swift:269`).

### 2. Dispatch in `PenRenderer.processNode`

Insertion point: `PenRenderer.swift` around line 325, after effects are collected and before children/content are drawn.

1. Extract background-blur effect the same way `blurEffect` is extracted (lines 320–325).
2. Build `clipPath` once via `PenShapeBuilder.buildPath(for: ref.node, rect: drawRect)` — reuse for background blur and for later clipping if `data.clip == true`.
3. Call `PenEffectRenderer.renderBackgroundBlur(...)` **after** opacity / transparency-layer setup (lines 293–297) but **before** `renderBlur` dispatch (line 341) and before `renderOwnContent`. Rationale: we want the node's own opacity to apply to the blurred backdrop (it's part of the node's composition), so capture happens inside the transparency layer.
4. Background blur and foreground blur can coexist: bg blur writes into the main context (or current transparency layer), then the existing foreground-blur path continues as before, rendering node content into its own offscreen. Order becomes: backdrop-blur → node content → foreground blur of node content.

### 3. `CIContext` caching

`PenEffectRenderer.renderBlur` currently allocates a fresh `CIContext` per call (`PenEffectRenderer.swift:244`). That's already wasteful for foreground blur and will compound with background blur. As part of this change, introduce a single shared `CIContext` (e.g. a static `let` on `PenEffectRenderer`), and use it for both `renderBlur` and `renderBackgroundBlur`. Note the existing code passes `.useSoftwareRenderer: true` — investigate whether we still need that. For now, keep the same options for parity.

### 4. Documentation updates (required by CLAUDE.md)

- Add DocC comment on `PenEffect.PenBackgroundBlurEffect` documenting renderer support.
- Update `Sources/Woodcase/Documentation.docc/` — the effects / rendering article (whichever describes the other effects) needs a section on background blur, including the bitmap-context limitation.
- No README change unless a new doc file is added.

## Known Limitations (v1)

Document these explicitly in the DocC article and in source comments:

1. **Bitmap contexts only.** If a caller passes their own non-bitmap `CGContext` via the `render(into:)` entry point (e.g. PDF, window context, `CGLayer`), background blur gracefully no-ops. Foreground content still renders. We log a one-line diagnostic on first miss per render.
2. **Parent transparency layers.** If a parent node has an active `beginTransparencyLayer` at capture time, `CGContext.makeImage()` may not see pixels that haven't been flushed out of the intermediate layer. Behavior: the backdrop appears as whatever was in the main context before the parent's transparency layer opened. We will document this as a known issue and plan a follow-up using Option B or a per-subtree readback strategy if users hit it in practice.
3. **Nested background blurs.** Supported and work correctly — the second `makeImage()` sees the result of the first blur composite.

## Open Questions

- **Opacity interaction.** Proposed: capture backdrop *inside* the node's transparency layer so node opacity applies to the blurred backdrop. Alternative: capture before, draw before, have opacity only affect node content. Need the user to confirm which matches Pencil's semantics in the web renderer. **I'll check the React emitter's behavior (`ReactEmitter+Styles.swift:387`) and cross-reference against Pencil's web rendering before finalizing.**
- **Zero-radius / disabled.** Treat as no-op (skip `makeImage()` entirely). Confirmed standard.
- **Scale field.** `PenBackgroundBlurEffect` only has `radius`, no separate `brightness`/`saturation` fields seen in iOS UIVisualEffectView. Assuming pure blur — no color matrix. Confirm from schema if we want to match CSS `backdrop-filter` more broadly later.

## TDD Sequence (Red → Green)

Per project rules, write all failing tests first, confirm red, then implement.

### New test file

`Tests/WoodcaseTests/Rendering/PenRenderer+BackgroundBlurTests.swift`

### Test cases (all must fail before implementation)

1. **Rendered without background blur (control).** A small fixture with a colored backdrop rectangle and an overlay node with no effects. Assert the center pixel under the overlay equals the overlay's fill color, and a pixel just outside equals the backdrop color. Verifies the fixture harness before we mutate anything.
2. **Background blur softens the backdrop.** Same fixture, but the overlay is a **transparent-fill** frame with `background_blur(radius: 20)`. Assert the backdrop pixels *visible through* the overlay are no longer equal to the original backdrop solid color (they should be a blended/averaged value). Assert pixels outside the overlay are unchanged (blur does not leak out).
3. **Clipping to node shape.** Overlay is an ellipse or rounded rect with background blur. Assert a pixel inside the node's bounding rect but *outside* the shape (a corner of the bounding box) is unchanged from the backdrop.
4. **Zero radius is a no-op.** Background blur with `radius: 0` produces pixel-identical output to the no-effect control.
5. **Disabled is a no-op.** `enabled: false` produces pixel-identical output to the no-effect control.
6. **Stacked with foreground blur.** Background-blurred node that also has a foreground blur effect renders without crashing and both effects visibly take effect. (Qualitative — just a smoke test for order-of-operations regression.)
7. **Nested background blur.** Two stacked background-blur nodes. Renders without crashing; inner blur visibly softens the backdrop further. Smoke test.
8. **Graceful degradation on non-bitmap context.** Render via `render(into:)` with a PDF context. Assert no crash, assert the node is still drawn (just without backdrop blur). This guards the nil-image fallback.

Fixtures are constructed programmatically (small in-memory `PenNode` trees), not as `.pen` files — matches existing CG renderer test style.

## Files Touched

- `Sources/Woodcase/Rendering/PenEffectRenderer.swift` — add `renderBackgroundBlur`, cache `CIContext`.
- `Sources/Woodcase/Rendering/PenRenderer.swift` — dispatch in `processNode` (~line 325).
- `Tests/WoodcaseTests/Rendering/PenRenderer+BackgroundBlurTests.swift` — new test file.
- `Sources/Woodcase/Documentation.docc/` — whichever article covers effects; add a section.
- Possibly a DocC comment update on `PenEffect.PenBackgroundBlurEffect`.

No model changes, no `.pen` parsing changes, no public API additions beyond DocC.

## Estimated Scope

Medium. The helper function is bounded, the dispatch point is a one-place edit, and the existing `renderBlur` provides the coordinate-system template. The bulk of the risk is in the test harness for pixel-level assertions and in the transparency-layer edge case. Call it ~1 focused session including tests and docs.
