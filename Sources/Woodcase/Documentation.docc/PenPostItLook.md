# The Post-it Look

How notes, prompts and contexts are drawn: one expansion into parts, which every renderer
paints.

## Overview

Penumbra's notes design (`../Penumbra/project/2026-10-11-notes-comments-and-spans.md`,
decisions 12–13) draws post-its, prompts and contexts as artwork, with one renderer and one
text engine, so `woodcase shot` matches Penumbra and caret editing is the canvas's own.
Comments are the exception: Penumbra draws them, so a note with `woodcase.type: comment` has
no expansion and the CG renderer draws nothing for it.

The look is decided once, by ``PenPostIt/expansion(of:width:height:style:measure:labels:identityColor:)``. It takes
the node and its laid-out size — grown to fit its text, <doc:NoteMarkdown> — and returns a
``PenPostItExpansion``: typed parts in paint order, each with a frame in the node's own
coordinates. A renderer only paints them:

- a **shape** part (``PenPostItExpansion/Shape``) as its node,
  ``PenPostItExpansion/Shape/node(id:frame:)`` — a `rectangle` or `ellipse` with a solid fill,
  an inner hairline and outer shadow effects, or a check mark's stroked `path` — through the
  node path it already draws, so its shadows and strokes are that renderer's own, already held
  to parity;
- a **text** part (``PenPostItExpansion/Text``) with ``PenTextLayout`` — string, style, runs,
  indents, color, top-aligned in the frame.

``PenRenderer/draw(_:in:)`` is the CG renderer's painter; RapidPro paints the same parts.
Nothing about the look — a color, a radius, where the author line sits, how wide the model
chip is, where a mention's pill or a checkbox lies — is decided by a renderer. Chrome labels
are measured inside the expansion with the layout's text measurer, and cut with an ellipsis
there when they do not fit.

The caller supplies two things the look cannot know:

- **The words.** The chrome's labels are typed, ``PenPostIt/Label`` — a prompt's and a
  context's title, Run, and the status for each ``PenPostIt/RunState`` — and the expansion
  takes `labels`, a function that spells each one. Woodcase's CG renderer and CLI pass
  ``PenPostIt/Label/english``; an editor passes its localized strings, which are what the
  chrome is measured in. Each chrome text names its label (``PenPostItExpansion/Text/label``).
  ``PenPostIt/Style`` holds no words.
- **Chosen colors.** `identityColor` returns the color a person chose, by identity, or `nil`
  to draw them in their ``ActorColor``.

```swift
let rect = layoutRects[note.id]!
if let expansion = PenPostIt.expansion(
    of: note, width: rect.width, height: rect.height,
    labels: { localized($0) }, identityColor: { chosenColors[$0] }
) {
    for part in expansion.parts { /* paint part.paint in part.frame */ }
}
```

### The parts

| Role | Variant | Paint | What it is |
|---|---|---|---|
| ``PenPostItExpansion/Role/plate`` | all | shape | The paper: the whole node, filled, with a hairline inside its edge and its shadows |
| ``PenPostItExpansion/Role/mentionPill`` | all | shape | A mention's pill, behind its text, in the person's identity color; one per line it sits on |
| ``PenPostItExpansion/Role/bullet`` | all | shape | A list bullet: a 5-point dot in the primary ink |
| ``PenPostItExpansion/Role/checkbox`` | all | shape | A checklist box, ``PenPostIt/Style/checkboxScale`` (1.17) times the body's cap height square, centered on the capitals; its frame is the hit rect (``PenPostItExpansion/checkboxes``) |
| ``PenPostItExpansion/Role/checkMark`` | all | shape | The check in a done box, stroked in the paper's color |
| ``PenPostItExpansion/Role/body`` | all | text | The markdown's display text, runs and indents, in ``PenPostIt/textFrame(of:width:height:style:)`` |
| ``PenPostItExpansion/Role/identityDot`` | note | shape | The author's dot, bottom left, in their identity color; ringed on dark paper |
| ``PenPostItExpansion/Role/author`` | note | text | The author's name beside the dot, in the secondary ink |
| ``PenPostItExpansion/Role/header`` | prompt, context | text | "▶ PROMPT" or "CONTEXT", tracked, in the secondary ink |
| ``PenPostItExpansion/Role/modelChip`` | prompt | shape | The model chip, a pill at the top right |
| ``PenPostItExpansion/Role/modelLabel`` | prompt | text | The prompt's `model` in the chip |
| ``PenPostItExpansion/Role/runButton`` | prompt | shape | The dark Run button, bottom right |
| ``PenPostItExpansion/Role/runLabel`` | prompt | text | "▶ Run" on it |
| ``PenPostItExpansion/Role/statusDot`` | prompt | shape | A dot in the run state's color (``PenPostIt/Style/statusColor(_:)``) |
| ``PenPostItExpansion/Role/status`` | prompt | text | "Queued · ben": the run state and `requestedBy`; absent before the first Run |
| ``PenPostItExpansion/Role/infoMark`` | context | shape | The ⓘ ring, top left |
| ``PenPostItExpansion/Role/infoGlyph`` | context | text | The "i" inside it |

There is no kind mark: the post-it kinds are gone (decision 1).

### The look

``PenPostIt/Style/standard`` holds every number; the defaults follow the rev 2 mockup.

- **Paper.** A note is its `woodcase.tint` — absent or malformed is Post-it yellow,
  ``PenPostIt/Tint/default`` — with corner radius 6, a 6% black hairline and two soft shadows
  (0,1 blur 3 at 10%; 0,4 blur 12 at 8%). A prompt is a white card, a context a quiet
  off-white card with a 10% hairline and no shadow; both have radius 8 and ignore a tint. The
  presets of spec §10 are ``PenPostIt/Tint``.
- **Ink.** Only black or only white, at an alpha (``PenPostIt/Ink``): black on paper whose
  relative luminance is above 0.36, white below. The body and a list's bullets take the
  primary ink (86% black or 92% white); labels, a checkbox's edge and a done box's fill the
  secondary (55%); a ticked checklist item's words the tertiary (38%), as a fill-only run,
  so it changes no line break.
- **List marks.** A bullet and a checkbox are drawn shapes, not glyphs. The markdown sets a
  placeholder for each (``PenNoteMarkdown/markerPlaceholder``, an em space) that holds its
  room before the tab, so the display text and its offset map stay one for one; the expansion
  sets the body with ``PenTextLayout`` and places each mark on its line: a bullet centered on
  the x-height, a checkbox centered on the capitals' midline and 1.17 times the body's cap
  height square (``PenPostIt/Style/checkboxScale``; Ben chose it on 2026-10-11 over a
  cap-height box, which read small).
  A done box is filled and carries a check mark; an open one is only edged.
- **Headings** stand off the text below by half a body line (``PenNoteMarkdown/headingSpacing``),
  a paragraph's ``PenParagraphIndent/spacingAfter``.
- **Author line.** A note with an author draws its identity dot (8) and name (11 pt, weight
  500) at the bottom inset, and adds that line and an 8-point gap to its bottom inset
  (``PenPostIt/bodyInsets(of:style:)``), so the layout grows the note by it.
- **No state.** A note has none — only comments are open or resolved (Ben's ruling,
  2026-10-11) — so a `state` a note still carries draws nothing, and `woodcase lint` names it
  (`note-state`).
- **Scale.** The chrome's text, dots and gaps scale with the note's font size over 13, so a
  note resized with its text (spec §5.9) keeps its proportions; radius, hairline, shadows and
  the 14-point ``PenPostIt/textInsets`` do not.

### Identity colors and mentions

An identity is drawn in one color everywhere: ``ActorColor``, the Jobs dashboard's hash of
the name, unless the caller supplies the color the person chose (Penumbra's notes design,
decision 7, ruled 2026-10-11). The author's dot takes it, and so does every pill of a
mention of them. ``PenPostItExpansion/identity`` and ``PenPostItExpansion/mentions`` carry
the name and the color drawn.

On paper that takes the white ink, the dot gets a thin light ring
(``PenPostIt/Style/identityRingOnDark``), so a dark hue still reads.

A **mention** is a pill behind its text, padded as CSS pads an inline element: the
mention's run carries ``PenTextRun/inlinePadding`` (``PenNoteMarkdown/mentionPadding``, 3
points at 13), which the text layout lays out as extra advance on each side of it. So the
space before a mention keeps its width, lines may break differently than without pills, and
drawing, measuring (and note growth), the editor's carets
(``PenTextLayout/init(note:size:color:)``) and RapidPro all agree with no second layout. The
pill covers the run and its padding, as tall as the body font's ascent and descent around the
baseline, fully rounded. At a paragraph's start the pill's left edge is on the text column
and the text sits the padding in; at the start of a line wrapped from the one before, Core
Text hangs the space that would carry the left padding, so the pill starts at the text with
no left padding. Its text is lettered in the ink the pill's color takes (``ActorColor/Ink``)
by a fill-only run. A mention that wraps draws a pill per line.

> Revised 2026-10-11: the first cut drew the padding into the neighboring spaces without
> laying it out; at 13 points the pill crowded its neighbors and poked past the text column.

### Sizes

A note lays out at 200 × 200 when unsized (<doc:PenPostItConvention>); a prompt or context at
``PenPostIt/cardDefaultWidth`` × ``PenPostIt/cardDefaultHeight``, the mockup's 240 × 160. All
three grow to fit their text plus their chrome and never shrink. A change to a note's author
needs layout, since it adds or removes the author line; a change to its state does not.

## Topics

### Expanding

- ``PenPostIt/expansion(of:width:height:style:measure:labels:identityColor:)``
- ``PenPostItExpansion``
- ``PenPostItExpansion/Part``
- ``PenPostItExpansion/Role``
- ``PenPostItExpansion/Paint``
- ``PenPostItExpansion/Shape``
- ``PenPostItExpansion/Hairline``
- ``PenPostItExpansion/Shadow``
- ``PenPostItExpansion/Text``
- ``PenPostItExpansion/Mention``
- ``PenPostItExpansion/Identity``
- ``PenPostItExpansion/Checkbox``

### The look

- ``PenPostIt/Style``
- ``PenPostIt/Label``
- ``PenPostIt/Ink``
- ``PenPostIt/Tint``
- ``PenPostIt/Variant``
- ``ActorColor``
- ``PenHexColor/relativeLuminance``
- ``PenHexColor/mixed(toward:by:)``

### Drawing and sizing

- ``PenRenderer/draw(_:in:)``
- ``PenPostIt/bodyInsets(of:style:)``
- ``PenPostIt/textFrame(of:width:height:style:)``
- ``PenPostIt/cardDefaultWidth``
- ``PenPostIt/cardDefaultHeight``
