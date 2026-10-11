# Note Markdown

A note's or comment's `content` is markdown: headings, bold, italic, lists, checklists and
`@mentions`, drawn styled while the file keeps the source.

## Overview

Penumbra's notes design (`../Penumbra/project/2026-10-11-notes-comments-and-spans.md`,
decisions 4, 6 and 7) makes a note's text markdown. Pen shows the source as written and keeps
it intact, so the file holds only the markdown; Woodcase derives the styling from it on every
read and never stores it — unlike a text node, whose runs live in `metadata.woodcase.spans`
(<doc:PenRichText>). An editor edits the raw markdown, as it edits variable tokens; at rest the
note is drawn styled.

``PenNoteMarkdown`` is the parse. ``PenNode/noteMarkdown`` parses a note's content at its font
size, and ``PenTextLayout/init(note:size:color:)`` sets it:

```swift
let markdown = node.noteMarkdown!            // "# Plan\n- [ ] Ship it, @claude"
markdown.displayText                         // "Plan\n☐\tShip it, @claude"
markdown.runs                                // the heading, and the mention
markdown.checklistItems[0].markerSourceRange // where "[ ]" is in the source
let layout = PenTextLayout(note: node, size: noteSize)
```

### The subset

Notes are line-oriented: every newline in the source is a newline on the note — no
paragraph reflow, as in a chat message — and inline styling never crosses a line.

| Source | Displays | Styling |
|---|---|---|
| `# `, `## `, `### ` at a line's start | the heading's words | ``PenNoteMarkdown/headingScales`` (1.5×, 1.25×, 1.1× the note's size), weight 700 |
| `**bold**` | `bold` | weight 700 |
| `*italic*`, `_italic_` | `italic` | italic |
| `- `, `* `, `+ ` | `•` and a tab | a hanging indent |
| `1. `, `1) ` | the number as written and a tab | a hanging indent |
| `- [ ] `, `- [x] ` | `☐` or `☑` and a tab | a hanging indent; a ``PenNoteMarkdown/ChecklistItem`` |
| `@name` | `@name` as written | weight 600 (700 in bold or a heading), carrying ``PenTextRun/mention`` |
| `\*` (a backslash before punctuation) | `*` | none: the backslash is removed |

Emphasis follows CommonMark's delimiter rules — flanking, `_` never inside a word, the rule of
three — so `***both***`, `**a *b* c**` and `snake_case_name` read as on GitHub. Two leading
spaces, or a tab, nest a list item one level (``PenNoteMarkdown/spacesPerLevel``).

**Everything else shows as its source:** links, images, code spans, tables, block quotes,
HTML, a fourth-level heading, an unmatched `*`. Nothing is dropped. A code span is kept whole,
so a `**` or an `@` inside backticks is not styling. A mention's name is letters, digits, `-`,
`_` and inner `.`s; an `@` after a name character (an email address) is not a mention, and a
trailing `.` ends the sentence, not the name.

### Mentions

A mention is a run whose ``PenTextRun/mention`` names who is mentioned. It reaches the
renderer on ``PenTextSegment/mention``, so a renderer can draw it as a pill in that person's
identity color. Woodcase does not resolve names to colors: identity colors are the editor's
presence colors. The CG renderer has no pill: the run's weight is what it draws.
``PenNoteMarkdown/mentionedNames`` lists who a note mentions.

A text node's spans can carry a mention too: `mention` is a stored run key
(``PenTextRun/WireKey/mention``).

### Lists hang

A list item's marker sits at its level's indent and its words one
``PenNoteMarkdown/listIndent`` (1.5 × the note's font size) further in, on every line. That is
the span model's one paragraph-level key, ``PenParagraphIndent``: a paragraph's first-line
indent, its head indent, and a tab stop at the head indent, so the tab after the marker lands
the first line's words where the wrapped lines start. ``PenTextLayout`` and
``PenTextMeasurer`` both honor it — measurement typesets an indented text through a frame, as
the drawing does — so a note's measured height is its drawn height.

### The offset map

``PenTextOffsetMap`` maps between source and display offsets, in UTF-16 code units on both
sides. It is a list of pieces tiling both strings: verbatim text maps offset for offset, and
syntax maps as a whole — removed syntax to an empty display range, a marker glyph to the
syntax it stands for.

- ``PenTextOffsetMap/sourceOffset(forDisplayOffset:)``: the source of the character at a
  display offset; hidden syntax before it is skipped.
- ``PenTextOffsetMap/sourceRange(forDisplayRange:)``: `bold` in `**bold**` maps to the source
  `bold`, not its asterisks.
- ``PenTextOffsetMap/displayOffset(forSourceOffset:)``: hidden syntax collapses to where its
  display starts.

### Checklists

Each ``PenNoteMarkdown/ChecklistItem`` has the source range of its `[ ]` or `[x]`
(``PenNoteMarkdown/ChecklistItem/markerSourceRange``), the display range of its box, and the
display range of its line. ``PenNoteMarkdown/checklistItem(atDisplayOffset:)`` finds the item
a click lands on, and ``PenNoteMarkdown/toggling(_:)`` returns the source with that one box
flipped — a three-code-unit edit, so the rest of the note is untouched:

```swift
let markdown = note.noteMarkdown!
if let item = markdown.checklistItem(atDisplayOffset: hit) {
    let newContent = markdown.toggling(item)   // write it to the note's `content`
}
```

### A note's style and its growth

A note's text style is read by ``PenNode/noteTextStyle``: each key from `metadata.woodcase`
first (Pen strips a note's own style, <doc:PenPostItConvention>), then the note's own property,
then ``PenTextStyle``'s default. The text is set in the note's box less
``PenPostIt/textInsets`` (``PenPostIt/textFrame(inNoteOfWidth:height:)``).

A note grows to fit its text and never shrinks: ``PenLayoutEngine`` lays a note out at the
larger of its set height and its text's height at its width plus the insets. Its width stays
as set, and nothing is clipped, faded or linted. The growth is the layout's, so `tree`, hit
testing and every renderer read one grown rect, and the file keeps the height that was set. A
change to a note's content or text style — on the node, or in `metadata.woodcase` — therefore
needs layout (``ChangeCategory``), as does a change to a text node's spans.

## Topics

### Parsing

- ``PenNoteMarkdown``
- ``PenNoteMarkdown/ChecklistItem``
- ``PenTextOffsetMap``
- ``PenNode/noteMarkdown``

### Setting

- ``PenNode/noteTextStyle``
- ``PenParagraphIndent``
- ``PenPostIt/textInsets``
- ``PenPostIt/textFrame(inNoteOfWidth:height:)``
- ``PenTextLayout/init(note:size:color:)``
