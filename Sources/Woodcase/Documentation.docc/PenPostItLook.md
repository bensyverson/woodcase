# The Post-it Look

How notes, prompts and contexts are drawn: one expansion into parts, which every renderer
paints.

## Overview

Penumbra's notes design (`../Penumbra/project/2026-10-11-notes-comments-and-spans.md`,
decisions 12–13) draws post-its, prompts and contexts as artwork, with one renderer and one
text engine, so `woodcase shot` matches Penumbra and caret editing is the canvas's own.
Comments are the exception: Penumbra draws them, so a note with `woodcase.type: comment` has
no expansion and the CG renderer draws nothing for it.

The look is decided once, by ``PenPostIt/expansion(of:width:height:style:measure:)``. It takes
the node and its laid-out size — grown to fit its text, <doc:NoteMarkdown> — and returns a
``PenPostItExpansion``: typed parts in paint order, each with a frame in the node's own
coordinates. A renderer only paints them:

- a **shape** part (``PenPostItExpansion/Shape``) as its node,
  ``PenPostItExpansion/Shape/node(id:frame:)`` — a `rectangle` or `ellipse` with a solid fill,
  an inner hairline and outer shadow effects — through the node path it already draws, so its
  shadows and strokes are that renderer's own, already held to parity;
- a **text** part (``PenPostItExpansion/Text``) with ``PenTextLayout`` — string, style, runs,
  indents, color, top-aligned in the frame.

``PenRenderer/draw(_:in:)`` is the CG renderer's painter; RapidPro paints the same parts.
Nothing about the look — a color, a radius, where the author line sits, how wide the model
chip is — is decided by a renderer. Chrome labels are measured inside the expansion with the
layout's text measurer, and cut with an ellipsis there when they do not fit.

```swift
let rect = layoutRects[note.id]!
if let expansion = PenPostIt.expansion(of: note, width: rect.width, height: rect.height) {
    for part in expansion.parts { /* paint part.paint in part.frame */ }
}
```

### The parts

| Role | Variant | Paint | What it is |
|---|---|---|---|
| ``PenPostItExpansion/Role/plate`` | all | shape | The paper: the whole node, filled, with a hairline inside its edge and its shadows |
| ``PenPostItExpansion/Role/body`` | all | text | The markdown's display text, runs and indents, in ``PenPostIt/textFrame(of:width:height:style:)`` |
| ``PenPostItExpansion/Role/identityDot`` | note | shape | The author's dot, bottom left, in the fallback identity color |
| ``PenPostItExpansion/Role/author`` | note | text | The author's name beside the dot, in the secondary ink |
| ``PenPostItExpansion/Role/resolvedLabel`` | note | text | "Resolved", bottom right of a resolved note |
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
  relative luminance is above 0.36, white below. The body takes the primary ink (86% black or
  92% white), labels the secondary (55%), a list's bullets and a ticked checklist item's
  words the tertiary (38%) — fill-only runs, so they change no line break.
- **Author line.** A note with an author draws its identity dot (8) and name (11 pt, weight
  500) at the bottom inset, and adds that line and an 8-point gap to its bottom inset
  (``PenPostIt/bodyInsets(of:style:)``), so the layout grows the note by it.
- **Resolved.** The tint is mixed 55% toward `#E7E7E7`, only the first shadow is cast, the body
  takes the secondary ink, and "Resolved" sits at the bottom right.
- **Scale.** The chrome's text, dots and gaps scale with the note's font size over 13, so a
  note resized with its text (spec §5.9) keeps its proportions; radius, hairline, shadows and
  the 14-point ``PenPostIt/textInsets`` do not.

### Identity colors and mentions

Identity colors are the editor's presence colors, which Woodcase does not know. The dot is
drawn in a fallback, ``PenPostIt/identityColor(for:style:)`` — a fixed palette indexed by
FNV-1a of the author string (``PenPostIt/identityHash(_:)``), so every platform and run agrees
— and ``PenPostItExpansion/identity`` names the author beside it. An editor repaints the
``PenPostItExpansion/Role/identityDot`` part in the person's presence color.

A mention is drawn by the CG renderer as the bold ink its run sets. Each one is listed in
``PenPostItExpansion/mentions`` — its UTF-16 range in the body's text and the name — so an
editor or RapidPro can lay a pill under it in the person's color, finding its rectangles with
the body's ``PenTextLayout`` geometry.

### Sizes

A note lays out at 200 × 200 when unsized (<doc:PenPostItConvention>); a prompt or context at
``PenPostIt/cardDefaultWidth`` × ``PenPostIt/cardDefaultHeight``, the mockup's 240 × 160. All
three grow to fit their text plus their chrome and never shrink. A change to a note's author
or state needs layout, since either can add or remove the author line.

## Topics

### Expanding

- ``PenPostIt/expansion(of:width:height:style:measure:)``
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

### The look

- ``PenPostIt/Style``
- ``PenPostIt/Ink``
- ``PenPostIt/Tint``
- ``PenPostIt/Variant``
- ``PenPostIt/identityColor(for:style:)``
- ``PenPostIt/identityHash(_:)``
- ``PenHexColor/relativeLuminance``
- ``PenHexColor/mixed(toward:by:)``

### Drawing and sizing

- ``PenRenderer/draw(_:in:)``
- ``PenPostIt/bodyInsets(of:style:)``
- ``PenPostIt/textFrame(of:width:height:style:)``
- ``PenPostIt/cardDefaultWidth``
- ``PenPostIt/cardDefaultHeight``
