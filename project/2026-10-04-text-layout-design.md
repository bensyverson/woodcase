# 2026-10-04 — One public text-layout API: design and plan

**Task:** `lHhvYV` "One public text-layout API" in [2026-10-04-penumbra-editor-support.md](2026-10-04-penumbra-editor-support.md); RapidPro's `tYtz4h` "Adopt Woodcase's shared text-layout API" follows it.\
**Source:** read-only research by a subagent of Penumbra's main thread; decisions by the main thread under Ben's delegation.

## Decisions (main thread, 2026-10-04)

1. **RapidPro's `spans` builder is deleted.** Production never produces spans (rich text left .pen in 2.17); keeping it means a second builder. The public `RenderTextContent` break is fine pre-launch.
2. **Caret and selection height is the line's pitch band** (top + i × pitch, height pitch), so bands tile the block as in Figma and Pen.
3. **Measurement shares font, kern and pitch with rendering now; alignment stays out of measurement** (frame-justifying in `measure` could shift `.layout.json` fixtures). Documented in the code.
4. **Woodcase's default face (SF Pro 16) is authoritative.** RapidPro's Inter 14 default is a parity bug. Probing Pen.app's true default is a separate question for later.
5. **Fixed-width-height text is not clipped** — CG, Pen exports and RapidPro all draw overflow. The caret simply extends past the box. Only notes clip (with a fade), driven by `overflows`. Penumbra's text-editing leaf is amended accordingly.
6. **Gating:** `PenTextStyle` and `PenTextGeometry` are Foundation-only; the builder `PenTextLayout` sits behind `canImport(CoreText)`. **Woodcase's layout and text stack is Apple-only today** (Package.swift declares macOS and iOS; 27 library files import CoreText unconditionally) despite the cross-platform rule; no Linux shaper is in scope here.

## Findings

Under `Sources/Woodcase` (W) or `Sources/RapidPro` (R).

- **`PenTextLines`** (W/Rendering/PenTextLines.swift) exposes `lines`, `lineStarts`, `pitch`, `firstBaseline`, `height`, `placed(inBoxOfHeight:)` (:21-98). It breaks lines with a tall CTFrame; it has no string ranges, vertical alignment, box or queries.
- **Three builders, not two.** CG's `buildAttributedString` (W/Rendering/PenTextRenderer.swift:87-141); RapidPro's copy (R/Metal/TextRasterizer.swift:306-443, plus a `spans` builder :326-401 and duplicated strikethrough :450-486); and `PenTextMeasurer.measure` (W/PenTextMeasurer.swift:34-74), which builds its own unaligned string.
- **Vertical offset is computed three times:** CG `renderText` (:41-48), `textInkBounds` (W/PenLayoutEngine+TextInk.swift:29-58), RapidPro `verticalOffset` (:202-210).
- **Parity bugs in RapidPro's copy:** default Inter 14 vs Woodcase's SF Pro 16 (R/Conversion/PenTextData+RenderTextContent.swift:57-58) — an unstyled text draws at 14 in a box measured at 16; weight quantized to 9 names, anything else regular (:13-26, so a variable-font 450 renders 400); Float vs Double for size, lineHeight, letterSpacing (pitch rounding can flip at .5); ink bounds by `useGlyphPathBounds` vs Woodcase's per-glyph outline union.
- **Neither renderer clips or reads `textGrowth`;** growth affects measurement only (W/PenLayoutEngine.swift:656-693). An empty text measures as one line of " " but draws nothing.
- **Notes need the same layout** for body and author label (`NoteData` holds only `content` today).

## Design

1. **`PenTextStyle`** (public, `Friendly`, Foundation-only): family, size, weight (CSS Double), italic, letterSpacing, lineHeight multiple, align, alignVertical, underline, strikethrough. Defaults applied once, here. `init(_ data: PenNode.TextData)`; `init(note:)` arrives with the notes work. RapidPro's cache key.
2. **`PenTextLayout`** (`#if canImport(CoreText)`, holds CTLines, not Sendable): `init?(text:style:box:color: = black)` and `init?(_ data: TextData, box:)`. Exposes `attributedString`, `font`, `lines: PenTextLines`, `blockTop`, `placed` (y-up), `textSpace` (the y-down transform both renderers build by hand), `inkBounds`, `blockRect`, `overflows`, `geometry`. Color goes in the string before typesetting (CTLineDraw reads run colors) and never changes geometry.
3. **`PenTextGeometry`** (public value, Foundation-only, Sendable, Codable): per line its UTF-16 `stringRange`, baseline y, band, `start` x, trailing-whitespace width and caret offsets per index (from `CTLineEnumerateCaretOffsets`: bidi and clusters). Node-local, y-down, origin at the box's top-left. Queries: `caretRect(at:affinity:)` (`.upstream` = end of the earlier line at a soft wrap); `index(at:) -> (index, affinity)` clamped to the nearest band and grapheme-snapped; `selectionRects(for:)` per line in bands, extended to the box edge across a hard newline (as NSTextView does); `lineIndex(containing:affinity:)`; `lineRange(at:)`; `caretOffsets(onLine:)` for up/down at the same x. Word and paragraph boundaries stay with AppKit. Synthesized cases: empty text (one caret line at `firstBaseline`, x by alignment), a trailing newline (an extra empty line), carets past the box.

> **As built, 2026-10-10 (leaves `FVLEsK`, `AC2izc`):** `PenTextLayout.init(text:style:box:color:)` is not failable — an empty string is a layout with no lines, so an editor still gets its caret line; only `init?(_ data:box:color:)` fails, for absent or unresolved content. The box is a `CGSize`. Geometry uses Woodcase's `PenRect`/`PenPoint`/`PenSize` (`CGRect` is not `Hashable`); `index(at:)` returns a `PenTextGeometry.Position`, and `position(onLine:nearestX:)` is added for up/down. A line's end is a typed `Ending` (`softWrap`, `hardBreak`, `endOfText`). The shared multi-line fixture is the public `PenTextLayoutSample.multiLine`, in the library so Penumbra and RapidPro reach it by import. See `Sources/Woodcase/Documentation.docc/PenTextLayoutForEditors.md`.

**Consumers.** CG `renderText`, `textInkBounds` and `PenShadowSilhouette` use `PenTextLayout`; `measure` builds through the same style → attributes function. RapidPro's `RenderTextContent` stores `style` + `string`; `rasterize` builds a `PenTextLayout` and draws `placed` through `textSpace` with `inkBounds`. Penumbra builds a `PenTextLayout` from the expanded node's `TextData` with the in-progress string and the node's rect, maps view ↔ node-local through the node's world transform, and draws marked text as an overlay underline from `selectionRects`, so layout stays identical to what RapidPro draws.

## Plan

`job import project/2026-10-04-text-layout-design.md --parent lHhvYV`. RapidPro's leaves are in [../../RapidPro/project/2026-10-04-text-layout-adoption.md](../../RapidPro/project/2026-10-04-text-layout-adoption.md).

```yaml
tasks:
  - title: "PenTextStyle and one attributed-string builder"
    ref: t-style
    desc: "Design: project/2026-10-04-text-layout-design.md, layer 1 and decisions 3–4. New Rendering/PenTextStyle.swift; PenTextRenderer.swift:87-153; PenTextMeasurer.swift:34-74; +Decorations.swift (make the strikethrough constants and drawStrikethrough public for RapidPro)."
    criteria:
      - "A public test (no @testable) builds an attributed string from a PenTextStyle"
      - "The CG renderer, ink measurement and measure share one builder, and a grep test finds no other CFAttributedStringCreate in the text path"
      - "render-text*, text-line-height-rounding and text-natural-line-height PNG MAE and .layout.json fixtures are unchanged"
  - title: "PenTextLayout: lines placed in a box"
    ref: t-layout
    blockedBy: [t-style]
    desc: "Design: project/2026-10-04-text-layout-design.md, layer 2. Rendering/PenTextLayout.swift; PenTextRenderer.swift:22-74; PenLayoutEngine+TextInk.swift; PenShadowSilhouette.swift:60."
    criteria:
      - "The CG renderer and textInkBounds place lines only through PenTextLayout, and the vertical-offset math exists once"
      - "Render fixtures are unchanged"
      - "PenTextLayout.inkBounds equals today's textInkBounds on the render-text fixtures"
  - title: "Editor geometry: caret, hit-test and selection"
    ref: t-geometry
    blockedBy: [t-layout]
    desc: "Design: project/2026-10-04-text-layout-design.md, layer 3 and decision 2. Rendering/PenTextGeometry.swift (Foundation-only), PenTextLayout.swift, a DocC article on text layout for editors. Add a multi-line fixture (wrapped, centered, justified, hard newline, trailing newline) that Penumbra's contract test and RapidPro's adoption reuse."
    criteria:
      - "On the multi-line fixture, index(at: caretRect(i).midPoint) returns i for every grapheme index and affinity"
      - "The union of selectionRects(0..<n) covers each line band from start to end with no overlap between lines"
      - "Empty text and a trailing newline yield a caret line at Pen's baseline"
      - "Surrogate pairs and an emoji ZWJ sequence never yield a mid-cluster index"
  - title: "Note text through PenTextLayout"
    ref: t-note
    blockedBy: [t-layout]
    desc: "Design: project/2026-10-04-text-layout-design.md, decision 5. PenTextStyle init(note:) and the note renderer. Blocked also by SuCn6G's model/look leaves (see that task's design doc)."
    criteria:
      - "The note body and author label are laid out through PenTextLayout in the inset box, and the CG note renderer draws through it"
      - "overflows is true for c41x's overflowing post-it, and both the lint and the clip-with-fade read it"
```
