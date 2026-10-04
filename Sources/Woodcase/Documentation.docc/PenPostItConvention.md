# The Post-it Convention

Sized notes, and the metadata keys that make a note a post-it with a kind, a state, an
author and a tint.

## Overview

A `note` is a sticky note on the canvas. Pen's schema declares
`Note extends Entity, Size, TextStyle`, so a note carries a `width`, a `height` and the
eleven TextStyle keys (``PenTextStyleProperties``) beside its `content`, and nothing paintable —
no fill, no stroke. `prompt` and `context` take the same keys but are not drawn.

### Size

A note whose `width` or `height` is absent, or not above zero, lays out at
``PenPostIt/defaultSize`` — 200 points — on that axis. Pen saves a note it was never
given a size for as `width: 0, height: 0`, so that case matters: the default is applied
in layout (``PenPostIt/layoutSizing(_:)``), not written into the file, so `tree`, hit
testing and the renderers read one 200×200 rect while the file keeps what Pen wrote. The
`note-unsized` lint notice (<doc:WoodcaseLint>) suggests writing the size.

```bash
woodcase set board.pen Board/Sticky kind.width=240 kind.height=160 kind.fontSize=15
```

A note's size change needs layout; a change to its text or TextStyle only a redraw,
because a note's box never grows to fit its text.

### The convention

A note is a *post-it* under the convention when its `metadata.type` is
``PenPostIt/typeValue`` (`"postit"`). Pen keeps arbitrary metadata keys, so the
convention lives there rather than in properties of its own:

| Key | Takes | Holds |
|---|---|---|
| `type` | `postit` | Marks the metadata as a post-it's |
| `kind` | `question`, `answer`, `reference` | What the post-it is for (``PenPostIt/Kind``) |
| `state` | `open`, `resolved` | Whether it still asks for attention (``PenPostIt/State``) |
| `author` | any string | Who wrote it |
| `leaf` | any string | The task it belongs to, such as a `job` id |
| `stage` | any string | The part of the work, or the board lane, it sits in |
| `tint` | `#RRGGBB` | The paper color; absent is Post-it yellow |
| `copiedFrom` | any string | On a copy, the original author, until the copier first edits it |

```json
{ "type": "note", "name": "Device check", "content": "Does the scanner …",
  "metadata": { "type": "postit", "kind": "question", "state": "open",
                "author": "claude", "leaf": "pODcm0", "stage": "Capture" } }
```

`woodcase schema postit` prints the same table from ``PenPostIt/Key``, and
``SchemaPostItReport`` is its machine-readable form.

**Authorship.** `author` is the post-it's creator. A copy keeps `author` and sets
`copiedFrom` to it; the first edit by whoever made the copy replaces `author` with their
identity and clears `copiedFrom` (Ben's ruling of 2026-10-04 on R10's "whoever edited it
after copying"). The convention types and validates both keys; performing the rewrite on
copy and edit belongs to the editing session, not to this convention.

### Reading

``PenPostIt/Metadata`` reads a node's metadata as typed values, and is `nil` for a node
that is not a post-it. Reading is lenient, because a file is: a value the convention
does not spell reads as ``PenPostIt/Metadata/Field/unrecognized(_:)`` holding what the
file wrote.

```swift
if let postIt = PenPostIt.Metadata(node) {
    if postIt.kind == .valid(.question), postIt.state == .valid(.open) {
        print("open question from \(postIt.author ?? "someone")")
    }
    let paper = postIt.tint?.value // a PenHexColor, or nil for Post-it yellow
}
```

### Writing

An agent's write is held to the convention; a file is not. A `set` of
`common.metadata` — a deep key such as `common.metadata.kind=question` is folded into the
whole object first — and every node of an `add` or `replace` subtree go through
``NodePropertyCodec/checkAuthoredPostIt(_:on:)`` and
``NodePropertyCodec/checkAuthoredPostIts(in:current:)``. A misspelled kind or state, a
tint that is not `#RRGGBB`, or a non-string author, leaf, stage or `copiedFrom` is
refused with ``EditingError/postItMetadataRejected(nodeID:key:value:accepted:suggestion:)``
— code `postItMetadataRejected` — naming the spellings the key takes and, when one is
close, the one most likely meant:

```text
common.metadata.kind on the post-it Board/Sticky (Nte01) takes question, answer or reference, but the value given is "questoin" — did you mean `woodcase set board.pen Nte01 common.metadata.kind=question`? …
```

Only the keys a write *changes* are checked. A file that already holds a misspelling
opens, and a write that leaves that key at its current value passes, so legacy boards
stay editable. Metadata whose `type` is not `postit` is never checked.

## Topics

### Notes and post-its

- ``PenPostIt``
- ``PenPostIt/Metadata``
- ``PenPostIt/Key``
- ``PenPostIt/Kind``
- ``PenPostIt/State``
- ``PenPostIt/Violation``
- ``PenTextStyleProperties``
- ``SchemaPostItReport``
