# Rich Text

Styled runs over a text node's content: a bold word, an italic phrase, a colored or larger span — set, measured and drawn by the same text layout every consumer shares.

## Overview

The `.pen` format has had no rich text since 2.17: a text node's `content` is one string, or a `$variable`, in one style. Woodcase goes ahead of the format. A text node keeps its plain string in `content` — the words Pen shows — and its styling beside it as ``PenTextSpans``: the runs, and the text they were made for. Pen deletes a 2.10-style run array written into `content` (the node loses its words), so runs are never written there. They live **only** in the node's `metadata.woodcase.spans` (Ben's ruling, 2026-10-11): one source of truth, which the per-entry metadata merge already resolves, key by key (<doc:PenMetadataNamespace>). Pen keeps metadata it does not understand, so a file edited in Pen keeps its styling — and when Pen changes the words, styling over part of the text goes stale rather than wrong, while styling over all of it follows the new words (see Stale styling below).

There is no Pen reference to match: Pen cannot draw runs. Parity is between Woodcase's CG renderer and RapidPro, which draws the same runs through the same ``PenTextLayout``.

### A run

A ``PenTextRun`` covers ``PenTextRun/start`` up to ``PenTextRun/end`` and may set any of the character keys: family, size, CSS weight, italic, fill (a solid color, ``PenHexColor``), underline and strikethrough. It may also name who it mentions (``PenTextRun/mention``) — not a style but an identity, which ``PenTextStyle/segments(of:runs:)`` carries onto ``PenTextSegment/mention`` for a renderer to draw as a pill. And it may link to a URL (``PenTextRun/link``) — not a style either: a linked run draws exactly as its other keys say, with no color or underline of its own, since the app a link is pasted from gives it its color and underline as `fill` and `underline`, which travel as keys of their own (the integrator's ruling of 2026-10-18, leaf `69moYq`). A link over the whole text follows new words, as a whole-text style does. Code generation does not emit runs yet — neither the SwiftUI nor the React emitter sets a text's spans — so a link, like a bold word, is not in generated code. Each key it leaves `nil`, and every range no run covers, inherits the node's own style. Line height, letter spacing and alignment belong to the paragraph and are the node's alone.

```swift
var metadata = node.common.metadata ?? PenMetadata(type: nil)
metadata.textSpans = PenTextSpans(text: "Make this bold", runs: [
    PenTextRun(start: 10, end: 14, fontWeight: 700),
])
node.common.metadata = metadata
let layout = PenTextLayout(node, box: box)   // sets "bold" in the 700 face
```

**Offsets are UTF-16 code units** — the unit Core Text, `NSString`, `NSRange`, `NSTextInputClient` and ``PenTextGeometry`` count in, so an editor's caret index is a run offset with no conversion. Not graphemes ("👍🏽" is one grapheme, four code units), not scalars, not bytes. A run edge that falls inside a grapheme cluster is widened outward to the whole cluster when the text is set, so one character's glyphs are never split between faces; an editor should still write runs on caret boundaries.

**Overlaps.** Runs may overlap; where they do, a later run wins for the keys it sets. An editor can bold a selection by appending a run, and normalize the list whenever it likes. A run is clamped to the text; one that is empty or inverted after clamping sets nothing.

**Resolving.** ``PenTextStyle/segments(of:runs:)`` is the one place runs are resolved over a node's style: it partitions the text into ``PenTextSegment``s, each a range with its resolved ``PenTextStyle`` and its run fill. ``PenTextStyle/applying(_:)`` is one run over a style. An editor's inspector reads the style under the caret, or across a selection, from the segments.

### Stale styling

``PenTextSpans/text`` is the content the runs were made for. ``PenTextSpans/appliedRuns(to:)`` returns the runs while the content still equals it, code unit for code unit — two strings equal only by Unicode equivalence have different offsets. Once it differs, a run over part of the text is dropped, since where it belongs in new words cannot be known; a run that covered the whole text is stretched over the whole of the new content (Ben's ruling of 2026-10-15, leaf `0LwfSn`), except a mention, which names the words it was made for, and nothing is stretched over empty content. ``PenTextSpans/ignoredRuns(for:)`` lists what is dropped. ``PenNode/appliedRuns`` asks that of the node's literal content, read from its metadata, and every consumer reads it: measurement, ink, the renderer, ``PenTextLayout/init(_:box:color:)``, the overflow lint. ``PenNode/hasStaleTextSpans`` says when some run is dropped that way, which the `spans-stale` lint, `tree` (`⚠ stale runs`) and a `set` that changes the words report (<doc:WoodcaseLint>, <doc:WoodcaseEditor>). Stale runs are kept, not moved: re-anchoring them by diffing the old text against the new can come later.

An instance that overrides a component text's content keeps only the component's whole-text runs, by the same rule: the spans were made for the component's words. So a node whose words were changed by a tool that does not know about runs loses its partial styling everywhere at once. Anything that changes `content` must restate the spans for the new text, or they go stale — inside an instance, as spans of the instance's own (below).

### Inside an instance

A text inside a component instance takes rich text through an instance override, as every other instance edit does (Ben's ruling of 2026-10-11, Penumbra spec §7.6 (1)). The spans are a Woodcase-owned key, so the override stores them in its own metadata, `descendants[<key>].metadata.woodcase.spans` — on the `ref` node's own metadata for a text that is the component's root — and expansion lays that over the component text's metadata key by key (rule 6, <doc:PenMetadataNamespace>): the component's other keys still reach the instance, the component is never touched, and a `null` clears the component's spans on that instance alone. An instance without spans of its own shows the component's, and later edits to them.

An editor plans the write where the text is stored, as an inspector does (``EditPlanner/plan(_:routedAt:in:)``, or ``EditPlanner/routeWrites(_:at:in:)`` for values it computed): bolding a word writes `kind.spans`, with the content when the words changed too, and the plan is one override on the instance.

```swift
let spans = PenTextSpans(text: "Make this bold", runs: [PenTextRun(start: 10, end: 14, fontWeight: 700)])
let plan = try EditPlanner.plan(
    .set(["kind.spans": spans.metadataValue]),
    routedAt: .instanceDescendant(refID: "Ins01", descendantKey: "Ttl01"), in: document
)   // [.overrideDescendant(Ins01, Ttl01: metadata.woodcase.spans)]
```

The override is held to the shapes a `set` is (``EditingError/textSpansRejected(nodeID:reason:)``, naming the text by its expanded id). Stale detection runs against the content the instance shows: an instance's own spans whose words its content override changed are stale as a plain text's are — ``PenNode/appliedRuns`` and ``PenNode/hasStaleTextSpans`` read the expanded node — and the `spans-stale` lint reports them on the instance (``DocumentLinter/spansStaleFinding(instance:descendantKey:in:)``), as an `override` that makes them stale does. Pen drops override metadata on save, so instance styling does not survive a round trip through Pen (`pen-drops-override`).

### Editing runs

An editor moves runs with every keystroke, so it keeps them flat: ``PenFlatTextRuns`` holds a text's runs sorted, never overlapping, each setting a key, touching neighbors with the same keys merged. Flattening a file's overlapping runs gives the same styling (a later run still wins for the keys it sets), and from then on every edit is plain arithmetic:

```swift
var runs = PenFlatTextRuns(spans: node.textSpans, content: text)
runs.replace(range, insertedLength: typed.utf16.count, keys: runs.keys(at: range.lowerBound - 1))
runs.set(PenTextRun(start: 0, end: 0, fontWeight: 700), over: selection)   // bold
runs.clear(.fontWeight, over: selection)                                   // un-bold
let spans = runs.spans(for: draft)   // nil once no run is left: remove the spans
```

``PenFlatTextRuns/replace(_:insertedLength:keys:)`` follows an insert, a delete or a replacement: runs before it stay, runs after it shift, a run it cuts keeps its parts outside it, and the inserted text takes the keys given. Un-bolding a range *clears* its weight (``PenFlatTextRuns/clear(_:over:)``) so the node's own weight shows there, rather than writing a regular weight over it. ``PenFlatTextRuns/stretches(in:)`` and ``PenFlatTextRuns/keys(at:)`` read the keys back for an inspector or a Format menu.

Stale spans start as the runs they still apply — their whole-text runs, stretched (``PenFlatTextRuns/init(spans:content:)``): that is what draws, so nothing visible is lost, and the spans written back are fresh for the current content and replace them — which is what a Format command on stale text does.

A run's keys are one list, ``PenTextRun/StyleKey``: overlaying (``PenTextRun/overlaid(by:)``), clearing (``PenTextRun/clear(_:)``), comparing (``PenTextRun/hasSameKeys(as:)``) and flattening all walk it, so a key added to ``PenTextRun`` reaches all of them, and a test fails until the new property has its case.

### Underline and strikethrough survive Pen

Pen strips a text node's own `underline` and `strikethrough` when it opens a file, and
keeps its metadata (`project/2026-09-26-what-pen-drops-from-a-file.md`). So whenever a
text of plain content carries either natively, Woodcase also writes them into
`metadata.woodcase.textDecoration` (``PenTextDecoration``), with the content they were
made for. ``PenParser`` keeps the two in step on every read and write
(``PenDocument/protectingTextDecoration()``): a native key a file no longer writes is
restored from the protection, a key it does write wins, and the protection is then
rewritten from the native keys. So a file saved in Pen reads
underlined and struck through, draws so on every target, and is written with the native
keys back. Both keys cover the whole text, so words edited in Pen keep them, as they keep
a whole-text run of a text's spans: the stale protection still restores, and is made
again for the new words (Ben's ruling of 2026-10-15, leaf `0LwfSn`). A text whose content is a variable has no
literal to protect against and is not protected. Probed with headless Pen (pen CLI
0.3.11, 2026-10-15) on `text-decoration.pen`, Woodcase's own write, and its save
`text-decoration.pen-saved.pen` (`PenTextDecorationTests`, leaf `kyrTTL`).

It is its own key rather than a whole-text run in `spans`: spans are the author's
styling, written whole by an editor, so a run kept in step with the native keys could
not be told from one the author made.

### Storage

`metadata.woodcase.spans` holds ``PenTextSpans/metadataValue``, read back by ``PenTextSpans/init(metadataValue:)``:

```json
"metadata": { "type": "woodcase", "woodcase": { "spans": {
  "text": "Make this bold",
  "runs": [ { "start": 10, "end": 14, "fontWeight": "700", "fill": "#E5484D" },
            { "start": 0, "end": 4, "fontStyle": "italic" } ]
} } }
```

Each run has `start` and `end` and only the style keys it sets, spelled as the format spells a text node's own (``PenTextRun/WireKey``): `fontWeight` a string (`"700"`; a keyword such as `"bold"` reads too), `fontStyle` `"italic"` or `"normal"`, `fill` a hex color, `fontSize` a positive number, `underline` and `strikethrough` booleans, `mention` a non-empty name, `link` a non-empty URL string. Offsets must lie inside `text`. Anything else — an unknown key, a misspelled value — is refused on an authored write (``EditingError/textSpansRejected(nodeID:reason:)``) and read from a file as no spans, so the text draws plain. Code reads and writes them through ``PenMetadata/textSpans``, which goes through ``PenMetadata/subscript(woodcase:)`` and types metadata that had no type.

A 2.10 document's run array is moved here by ``PenRichTextMigrationRule`` when it is opened: the words flatten into `content`, the styling becomes spans over them, and only what spans cannot hold (letter spacing, a `$variable`, …) is reported as dropped.

### Setting and measuring

``PenTextStyle/attributedString(_:runs:indents:for:)`` sets each segment in its own resolved font and decorations and, when drawn, its run's fill or the node's color; the paragraph style (line pitch, alignment, letter spacing) is the node's throughout. ``PenTextLayout/init(text:style:runs:indents:box:color:)`` is the layout call for a text with runs — RapidPro's rasterizer and an editor typing a draft call it directly — and ``PenTextMeasurer/measure(_:fontFamily:fontSize:fontWeight:fontStyle:letterSpacing:lineHeight:maxWidth:runs:indents:)`` sizes it, so a bold run that pushes a word to the next line in the drawing pushes it there in layout too. ``PenLayoutEngine`` hands a node's applied runs to its ``TextMeasurer`` in the ``PenTextMeasureRequest`` it measures, and the run-scoped `TextSizeCache` keys its sizes on that request with the colors taken out (``PenTextMeasureRequest/ignoringColor``), so recoloring a word does not measure it again.

### Paragraph indents

Runs style characters; a paragraph's indents and spacing cannot ride on them. ``PenParagraphIndent`` is the one paragraph-level key: a first-line indent, a head indent for the wrapped lines, a tab stop at the head indent, and the space after the paragraph (``PenParagraphIndent/spacingAfter``), which ``PenTextLines/bands`` leaves between its last line and the next. ``PenTextLayout/init(text:style:runs:indents:box:color:)`` and the measurer (``PenTextMeasureRequest/indents``) both take them, so a hanging list item, or a heading's space after, measures as it draws. A note's markdown sets one per list item and per heading (<doc:NoteMarkdown>); a text node's spans have none yet — no `.pen` key carries them.

### Lines with mixed sizes

A line is as tall as the faces set on it need, as CSS sets a line box, with the node's own style as its strut:

- Each face on a line — the node's, and each run's — needs a height above the baseline and one below. Its pitch is ``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)`` at *its own* size: under an explicit `lineHeight` that multiplies each run's size, as CSS's unitless `line-height` does; with none, each face's natural line height. Its baseline sits in that pitch where Pen puts the node's (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``, half-leading).
- The line's band (``PenTextLines/Band``) is the most any face needs above plus the most any needs below, its baseline between. Bands stack: each line starts where the last ended.

So a larger run pushes its line's baseline down and every later line lower; a smaller run never makes a line shorter than the node's pitch; and a line in the node's face alone is exactly one pitch tall with its baseline at the node's first baseline — the lines every text without runs has always set, byte for byte. Faces Core Text substitutes for missing glyphs (an emoji) do not count: only the faces the style and runs name. Glyphs of different sizes share the line's baseline.

``PenTextLines/bands`` holds each line's band, ``PenTextLines/placed(inBoxOfHeight:)`` places each line at its band's baseline, the block's height (``PenTextLayout/blockHeight``) is the bands' total, and ``PenTextGeometry`` gives each line its own band, so a caret on a line holding a larger run is as tall as that line. A text that ends in a newline has its synthesized caret line one node pitch tall below the last band.

### Drawing

On the solid route a run's fill is its Core Text color. On the glyph-outline route (a gradient, an image, a stack) a run with a fill of its own is marked with ``PenTextRenderer/runFillKey``: it is kept out of the paint's clip and drawn by Core Text in its own color, its underline and strikethrough bars with it (``PenGlyphOutlines/ColorRun``). A node with no paint of its own draws nothing — except its runs that have a fill, which draw in their color. Underline follows each run's own font; strikethrough is struck per run in its color, as for a whole node.

Another renderer draws a text node's spans through the same layout: `PenTextLayout(node, box: box, color: color)` reads the node's applied runs from its metadata, or, for a renderer that carries the text and its style apart from the node (RapidPro's `RenderTextContent`), `PenTextLayout(text: content, style: PenTextStyle(data), runs: node.appliedRuns, box: box, color: color)`. It then draws ``PenTextLayout/placed`` through ``PenTextLayout/textSpace`` as for any text, and honors ``PenTextRenderer/runFillKey`` on the outline route.

## Topics

### The model

- ``PenTextRun``
- ``PenTextSpans``
- ``PenNode/textSpans``
- ``PenNode/appliedRuns``
- ``PenNode/hasStaleTextSpans``
- ``DocumentLinter/spansStaleFinding(instance:descendantKey:in:)``

### Editing

- ``PenFlatTextRuns``
- ``PenTextRun/StyleKey``
- ``PenTextRun/noKeys``
- ``PenTextRun/keysOnly``
- ``PenTextRun/setsNoKey``
- ``PenTextRun/hasSameKeys(as:)``
- ``PenTextRun/over(_:)``
- ``PenTextRun/overlaid(by:)``
- ``PenTextRun/sets(_:)``
- ``PenTextRun/clear(_:)``
- ``PenTextRun/clearing(_:)``
- ``PenTextRun/taking(_:from:)``

### Storage

- ``PenMetadata/textSpans``
- ``PenTextSpans/init(metadataValue:)``
- ``PenTextSpans/metadataValue``
- ``PenTextSpans/WireError``
- ``PenTextRun/WireKey``
- ``PenHexColor/hex``

### Resolving and setting

- ``PenParagraphIndent``
- ``PenTextSegment``
- ``PenTextStyle/segments(of:runs:)``
- ``PenTextStyle/applying(_:)``
- ``PenTextLines/Band``
- ``PenTextRenderer/runFillKey``
