# The Post-it Convention

Sized notes, and the metadata keys that give a note a type, a state, an author, a tint
and a text style.

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
woodcase set board.pen Board/Sticky kind.width=240 kind.height=160
```

> Revised 2026-10-11 (leaf uAzSie, notes design decision 4): a note **grows to fit its
> text** and never shrinks below its set height; its width stays as set. So a change to its
> size, its text or its text style needs layout. See <doc:NoteMarkdown>.

> Note: Pen strips a note's own text style (and any `fill`) when it loads a file
> (`project/2026-10-11-what-pen-keeps-on-a-note.md`), so the style a note should keep
> lives in its metadata, under `woodcase.fontSize` and the other text-style keys below.

### The convention

> Revised 2026-10-11 (Penumbra `project/2026-10-11-notes-comments-and-spans.md`,
> decisions 1–3 and 8): every note is a post-it; the kinds (`question`, `answer`,
> `reference`) are gone; and every key lives under `metadata.woodcase`
> (<doc:PenMetadataNamespace>).

Every `note` is a post-it. Pen keeps arbitrary metadata keys, so the convention lives
under the Woodcase namespace, `metadata.woodcase`, rather than in properties of its own
(``PenPostIt/keys``):

| Key | Takes | Holds |
|---|---|---|
| `type` | `postit`, `comment` | What the note is (``PenPostIt/NoteType``); absent is a post-it |
| `state` | `open`, `resolved` | Whether it still asks for attention (``PenPostIt/State``) |
| `author` | any string | Who wrote it |
| `leaf` | any string | The task it belongs to, such as a `job` id |
| `stage` | any string | The part of the work, or the board lane, it sits in |
| `tint` | `#RRGGBB` | The paper color; absent is Post-it yellow |
| `copiedFrom` | any string | On a copy, the original author, until the copier first edits it |
| `anchor` | any JSON | On a comment's first message, the node and point it is about |
| `replyTo` | any string | On a comment reply, the id of the thread's first message |
| `fontFamily`, `fontWeight`, `fontStyle` | any string | The note's text style |
| `fontSize`, `letterSpacing`, `lineHeight` | any number | The note's text style |
| `textAlign`, `textAlignVertical` | as on a text node | The note's text alignment |

```json
{ "type": "note", "name": "Device check", "content": "Does the scanner …",
  "metadata": { "woodcase": { "state": "open", "author": "claude",
                              "leaf": "pODcm0", "stage": "Capture" } } }
```

`woodcase schema postit` prints the same table from ``PenPostIt/keys``, and
``SchemaPostItReport`` is its machine-readable form.

**Old spellings.** A note written before the namespace carries `metadata.type: "postit"` (rewritten to `"woodcase"` when its keys move in)
and its keys bare beside it (`state`, `author`, `tint`, …). They are still read, the
namespace winning where both are written; a write moves the key it writes in, and
`woodcase migrate` moves them all (<doc:PenMetadataNamespace>). A legacy `kind` is left
as written and read by nothing.

**Authorship.** `author` is the post-it's creator. A copy keeps `author` and sets
`copiedFrom` to it; the first edit by whoever made the copy replaces `author` with their
identity and clears `copiedFrom` (Ben's ruling of 2026-10-04 on R10's "whoever edited it
after copying"). The convention types and validates both keys; performing the rewrite on
copy and edit belongs to the editing session, not to this convention.

**Comments** are notes too, one per message: `woodcase.type: comment`, the first message
carrying `anchor` and `state`, each reply `replyTo` and `author`. The keys are typed
here; the comment workflow is not.

### Reading

``PenPostIt/Metadata`` reads a note's metadata as typed values — every note has one —
and, for another node, is `nil` unless its metadata carries a convention key. Every key
is read through ``PenMetadata/subscript(woodcase:)``, so old spellings read too. Reading
is lenient, because a file is: a value the convention does not spell reads as
``PenPostIt/Metadata/Field/unrecognized(_:)`` holding what the file wrote.

```swift
if let postIt = PenPostIt.Metadata(node) {
    if postIt.type != .valid(.comment), postIt.state == .valid(.open) {
        print("open post-it from \(postIt.author ?? "someone")")
    }
    let paper = postIt.tint?.value // a PenHexColor, or nil for Post-it yellow
}
```

### Writing

An agent's write is held to the convention; a file is not. A `set` of
`common.metadata` — a deep key such as `common.metadata.woodcase.state=resolved` is
folded into the whole object first, and stored under the namespace
(<doc:PenMetadataNamespace>) — and every node of an `add` or `replace` subtree go through
``NodePropertyCodec/checkAuthoredPostIt(_:on:)`` and
``NodePropertyCodec/checkAuthoredPostIts(in:current:)``. Every key of
``PenMetadata/WoodcaseKey`` is held to its ``PenMetadata/WoodcaseKey/shape``: a misspelled
type or state, a tint that is not `#RRGGBB`, a non-string author, or a font size that is
not a number is refused with
``EditingError/postItMetadataRejected(nodeID:key:value:accepted:suggestion:)`` — code
`postItMetadataRejected` — naming the spellings the key takes and, when one is close, the
one most likely meant:

```text
common.metadata.woodcase.state on Board/Sticky (Nte01) takes open or resolved, but the value given is "reslved" — did you mean `woodcase set board.pen Nte01 common.metadata.woodcase.state=resolved`? …
```

Only the keys a write *changes* are checked, read in either spelling. A file that
already holds a misspelling opens, and a write that leaves that key at its current value
passes, so legacy boards stay editable. A bare key on metadata that is not a post-it's
is not Woodcase's, and is never checked.

## Topics

### Notes and post-its

- ``PenPostIt``
- ``PenPostIt/Metadata``
- ``PenPostIt/keys``
- ``PenPostIt/NoteType``
- ``PenPostIt/State``
- ``PenPostIt/Violation``
- ``PenTextStyleProperties``
- ``SchemaPostItReport``
- <doc:PenMetadataNamespace>
- <doc:NoteMarkdown>
