# Text Layout for Editors

One layout call places a text's lines for every renderer and for an editor's caret, so the caret sits on the line that was drawn.

## Overview

A text node's lines are set once, by ``PenTextLayout``, and everything that needs to know where a line goes reads them from there: Woodcase's CG renderer draws them, ``PenLayoutEngine`` measures their ink, RapidPro's rasterizer draws them on the GPU path, and an editor reads carets, hit-tests and selections from the layout's ``PenTextLayout/geometry``. There is no second copy of the rule that places a line, so an editor cannot put a caret a pixel off the glyphs a renderer drew (`PenTextLayoutSourceTests` fails on a second `PenTextLines(…)` or `placed(inBoxOfHeight:)` call in the library).

The layout is three layers:

1. ``PenTextStyle`` — how a text is set, every default decided once (SF Pro 16, regular, natural line height, top-left). Plain data; also a renderer's cache key.
2. ``PenTextLayout`` — the style, a string and a box, set by Core Text: the attributed string, the lines (``PenTextLines``), where the block sits in the box (``PenTextLayout/blockTop``), each line's origin for `CTLineDraw` (``PenTextLayout/placed``), the y-down map a renderer draws them through (``PenTextLayout/textSpace``), the glyphs' ink (``PenTextLayout/inkBounds``) and whether the block overflows its box (``PenTextLayout/overflows``). Apple platforms only; it holds Core Text objects and lives for one draw or one edit.
3. ``PenTextGeometry`` — carets, lines and selection bands as a plain value: Foundation only, `Sendable` and `Codable`. Build it from the layout and keep it.

### Laying out a text node

```swift
let box = CGSize(width: rect.width, height: rect.height)
guard let layout = PenTextLayout(textData, box: box) else { return } // no literal content
context.concatenate(layout.textSpace)
for (line, origin) in layout.placed {
    context.textPosition = origin
    CTLineDraw(line, context)
}
```

An editor that is typing builds the layout from the in-progress string and the node's own style rather than from the node: `PenTextLayout(text: draft, style: PenTextStyle(textData), box: box)`. An empty string sets no lines and draws nothing, but its geometry still has a caret line.

### Coordinates

Everything is node-local: origin at the box's top-left, y growing downward, in points — except ``PenTextLayout/placed``, which is Core Text's y-up space, and which ``PenTextLayout/textSpace`` maps into the box. An editor maps a view point into node-local space through the node's world transform, queries the geometry, and maps the answer back. String positions are UTF-16 offsets, as `NSRange` and `NSTextInputClient` count them.

A block taller than its box is not clipped (Pen draws the overflow), so lines, carets and selections of a fixed-height text can lie past the box.

### Carets

Each line is a band one line pitch tall, starting at ``PenTextLayout/blockTop`` and tiling the block (``PenTextGeometry/Line/band``). A caret is zero wide and as tall as its band: ``PenTextGeometry/caretRect(at:affinity:)``. Carets stand only at grapheme-cluster boundaries — never inside a surrogate pair, a combining sequence or an emoji ZWJ sequence — at the offsets Core Text reports for them (`CTLineEnumerateCaretOffsets`, which follows clusters and bidi).

At a soft wrap one index ends a line and starts the next. ``PenTextGeometry/Affinity`` says which: `.upstream` is the end of the earlier line, `.downstream` the start of the later, as in `NSTextView`.

Two lines exist only in the geometry. An empty text has one caret line where Pen would set a one-line text — its baseline at Pen's first baseline, its x by alignment (left, center or right of the box). A text that ends in a newline has an empty caret line one pitch below its last.

### Hit-testing and moving

``PenTextGeometry/index(at:)`` answers the caret nearest a point on the line whose band holds it; a point above the text hits the first line and one below it the last, so a drag past the text keeps selecting. A click past the end of a wrapped line answers that line's end, upstream. Moving up or down keeps x: ``PenTextGeometry/position(onLine:nearestX:)`` with the line above or below (``PenTextGeometry/lineIndex(containing:affinity:)``). Home and End are a line's first and last caret (``PenTextGeometry/Line/carets``).

Hit-testing the midpoint of the caret at `i` returns `i` — with its affinity at a soft wrap — for every grapheme index of every sample in ``PenTextLayoutSample/multiLine`` (`PenTextGeometryTests`).

### Selection

``PenTextGeometry/selectionRects(for:)`` returns one rect per line a range touches, filling that line's band between the selection's carets. A selection that continues past a line's end, taking in its newline or running on past a soft wrap, reaches the box's right edge on that line, as `NSTextView` draws it; one that stops exactly at a soft wrap ends at that line's last caret. Bands tile, so the rects of different lines never overlap. The same rects underline marked text during input-method composition.

### The shared fixture

``PenTextLayoutSample/multiLine`` is the text every consumer checks itself against: a paragraph that wraps, a hard newline, a blank line, a combining accent, a surrogate pair, an emoji ZWJ sequence and a trailing newline, set left, centered, right and justified in the default face. It lives in the library, not in a test bundle, so Penumbra's contract test and RapidPro's adoption test reach the same values through `import Woodcase`.

### What an editor adds

The geometry covers what `NSTextInputClient` asks of the layout: `characterIndex(for:)` is ``PenTextGeometry/index(at:)`` after mapping the screen point to node-local space; `firstRect(forActualRange:)` is the first of ``PenTextGeometry/selectionRects(for:)`` (or the caret rect for an empty range), mapped to the screen. Word and paragraph boundaries are not here: take them from the platform's text system over the same string.
