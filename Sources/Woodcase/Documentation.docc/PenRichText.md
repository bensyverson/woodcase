# Rich Text

Styled runs over a text node's content: a bold word, an italic phrase, a colored or larger span — set, measured and drawn by the same text layout every consumer shares.

## Overview

The `.pen` format has had no rich text since 2.17: a text node's `content` is one string, or a `$variable`, in one style. Woodcase goes ahead of the format. A text node keeps its plain string in `content` — the words Pen shows — and its styling beside it as ``PenTextSpans``: the runs, and the text they were made for. Pen deletes a 2.10-style run array written into `content` (the node loses its words), so runs are never written there; their storage is the node's `woodcase.spans` metadata key. Pen keeps metadata it does not understand, so a file edited in Pen keeps its styling — and when Pen changes the words, the styling goes stale rather than wrong (see Stale styling below).

There is no Pen reference to match: Pen cannot draw runs. Parity is between Woodcase's CG renderer and RapidPro, which draws the same runs through the same ``PenTextLayout``.

### A run

A ``PenTextRun`` covers ``PenTextRun/start`` up to ``PenTextRun/end`` and may set any of the character keys: family, size, CSS weight, italic, fill (a solid color, ``PenHexColor``), underline and strikethrough. Each key it leaves `nil`, and every range no run covers, inherits the node's own style. Line height, letter spacing and alignment belong to the paragraph and are the node's alone.

```swift
let spans = PenTextSpans(text: "Make this bold", runs: [
    PenTextRun(start: 10, end: 14, fontWeight: 700),
])
var data = PenNode.TextData(content: .literal("Make this bold"), spans: spans)
let layout = PenTextLayout(data, box: box)   // sets "bold" in the 700 face
```

**Offsets are UTF-16 code units** — the unit Core Text, `NSString`, `NSRange`, `NSTextInputClient` and ``PenTextGeometry`` count in, so an editor's caret index is a run offset with no conversion. Not graphemes ("👍🏽" is one grapheme, four code units), not scalars, not bytes. A run edge that falls inside a grapheme cluster is widened outward to the whole cluster when the text is set, so one character's glyphs are never split between faces; an editor should still write runs on caret boundaries.

**Overlaps.** Runs may overlap; where they do, a later run wins for the keys it sets. An editor can bold a selection by appending a run, and normalize the list whenever it likes. A run is clamped to the text; one that is empty or inverted after clamping sets nothing.

**Resolving.** ``PenTextStyle/segments(of:runs:)`` is the one place runs are resolved over a node's style: it partitions the text into ``PenTextSegment``s, each a range with its resolved ``PenTextStyle`` and its run fill. ``PenTextStyle/applying(_:)`` is one run over a style. An editor's inspector reads the style under the caret, or across a selection, from the segments.

### Stale styling

``PenTextSpans/text`` is the content the runs were made for. ``PenTextSpans/appliedRuns(to:)`` returns the runs only while the content still equals it, code unit for code unit — two strings equal only by Unicode equivalence have different offsets — and an empty list otherwise. ``PenNode/TextData/appliedRuns`` asks that of the node's literal content, and every consumer reads it: measurement, ink, the renderer, ``PenTextLayout/init(_:box:color:)``. So a node whose words were changed by a tool that does not know about runs draws plain everywhere at once. Anything that changes `content` must restate the spans for the new text, or they go stale.

### Setting and measuring

``PenTextStyle/attributedString(_:runs:for:)`` sets each segment in its own resolved font and decorations and, when drawn, its run's fill or the node's color; the paragraph style (line pitch, alignment, letter spacing) is the node's throughout. ``PenTextLayout/init(text:style:runs:box:color:)`` is the layout call for a text with runs — RapidPro's rasterizer and an editor typing a draft call it directly — and ``PenTextMeasurer/measure(_:fontFamily:fontSize:fontWeight:fontStyle:letterSpacing:lineHeight:maxWidth:runs:)`` sizes it, so a bold run that pushes a word to the next line in the drawing pushes it there in layout too. ``PenLayoutEngine`` hands a node's applied runs to its ``TextMeasurer`` in the ``PenTextMeasureRequest`` it measures, and the run-scoped `TextSizeCache` keys its sizes on that request.

### Lines with mixed sizes

A line is as tall as the faces set on it need, as CSS sets a line box, with the node's own style as its strut:

- Each face on a line — the node's, and each run's — needs a height above the baseline and one below. Its pitch is ``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)`` at *its own* size: under an explicit `lineHeight` that multiplies each run's size, as CSS's unitless `line-height` does; with none, each face's natural line height. Its baseline sits in that pitch where Pen puts the node's (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``, half-leading).
- The line's band (``PenTextLines/Band``) is the most any face needs above plus the most any needs below, its baseline between. Bands stack: each line starts where the last ended.

So a larger run pushes its line's baseline down and every later line lower; a smaller run never makes a line shorter than the node's pitch; and a line in the node's face alone is exactly one pitch tall with its baseline at the node's first baseline — the lines every text without runs has always set, byte for byte. Faces Core Text substitutes for missing glyphs (an emoji) do not count: only the faces the style and runs name. Glyphs of different sizes share the line's baseline.

``PenTextLines/bands`` holds each line's band, ``PenTextLines/placed(inBoxOfHeight:)`` places each line at its band's baseline, the block's height (``PenTextLayout/blockHeight``) is the bands' total, and ``PenTextGeometry`` gives each line its own band, so a caret on a line holding a larger run is as tall as that line. A text that ends in a newline has its synthesized caret line one node pitch tall below the last band.

### Drawing

On the solid route a run's fill is its Core Text color. On the glyph-outline route (a gradient, an image, a stack) a run with a fill of its own is marked with ``PenTextRenderer/runFillKey``: it is kept out of the paint's clip and drawn by Core Text in its own color, its underline and strikethrough bars with it (``PenGlyphOutlines/ColorRun``). A node with no paint of its own draws nothing — except its runs that have a fill, which draw in their color. Underline follows each run's own font; strikethrough is struck per run in its color, as for a whole node.

## Topics

### The model

- ``PenTextRun``
- ``PenTextSpans``
- ``PenNode/TextData/spans``
- ``PenNode/TextData/appliedRuns``

### Resolving and setting

- ``PenTextSegment``
- ``PenTextStyle/segments(of:runs:)``
- ``PenTextStyle/applying(_:)``
- ``PenTextLines/Band``
- ``PenTextRenderer/runFillKey``
