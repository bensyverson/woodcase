# Reading the Figma Clipboard

Take the HTML Figma puts on the clipboard to its embedded Kiwi schema and its message.

## Overview

When you copy in Figma, the selection lands on the pasteboard as HTML (`public.html` on
macOS). ``FigmaClipboardDecoder`` turns that HTML into a ``FigmaClipboard``: the metadata,
the container, and the schema and message its chunks hold. It works on bytes only, with no
AppKit or WebKit, so a CLI or a test can use it as readily as the editor.

```swift
let clipboard = try FigmaClipboardDecoder().decode(html: html)
clipboard.metadata.editorType            // "design"
clipboard.container.version              // 101 or 106 so far
clipboard.container.chunks.map(\.count)  // the compressed chunk lengths
clipboard.message["type"]?.enumName      // "NODE_CHANGES"
```

The message is generic Kiwi (<doc:KiwiDecoding>); turning its nodes into Pen nodes is a
separate step.

### The HTML

Figma writes two `<span>` attributes, each holding base64 inside an HTML comment:

```html
<span data-metadata="<!--(figmeta)BASE64(/figmeta)-->"></span>
<span data-buffer="<!--(figma)BASE64(/figma)-->"></span>
```

`figmeta` is JSON (``FigmaClipboardMetadata``); `figma` is the binary. The wrapper varies
by where the copy came from. The desktop app and Chromium browsers write the values raw
after a doubled `<meta charset>`. Safari re-serializes the fragment: no `<meta>`, inline
`style` attributes, and values escaped as `&lt;!--(figmeta)…(/figmeta)--&gt;`.
``FigmaClipboardPayload`` finds each attribute by name, decodes its character references
(`&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`, `&#NN;`, `&#xHH;`), then decodes the base64
between the markers, so every wrapper reads the same. Markers outside the attributes do not
count.

The desktop app wraps the web app, so figmeta's `environment` reads `www.figma.com` from
either; nothing in the payload tells a desktop copy from a browser one.

### The container

``FigKiwiContainer`` frames the binary: an 8-byte prelude (`fig-kiwi` on the clipboard;
files also use `fig-jam.` and `fig-deck`), a little-endian `UInt32` version, then chunks,
each a little-endian `UInt32` length and its bytes. The version is not a schema identifier:
captures at versions 101 and 106 carry the same schema byte for byte.

Chunk 0 is the Kiwi schema, raw deflate; chunk 1 is the message, zstd. The decoder inflates
the first with ``DeflateDecoder`` (Apple's Compression framework) and decodes the second
with ``ZstdDecoder`` (<doc:ZstdDecoding>), then reads the schema and decodes the message as
its `Message` definition (``FigmaClipboardDecoder/rootType``). Chunks after the second are
kept in the container and otherwise ignored.

### Trusting nothing

A clipboard can hold anything, so every step refuses rather than guesses, with a
``FigmaDecodeError`` that names the step:

- Each chunk length is checked against the bytes that remain before anything is copied.
- Each decompressor has a cap (``FigmaClipboardDecoder/maxSchemaSize``, 16 MiB by
  default, and ``FigmaClipboardDecoder/maxMessageSize``, 256 MiB), so a decompression bomb
  costs at most the cap.
- A zstd frame carries a magic number and the decoder demands exactly one frame. Raw
  deflate has neither magic nor checksum, and Apple's inflate does not check a stored
  block's length complement or refuse bytes after the final block, so the Kiwi schema
  decode that follows is the real check on chunk 0.

That last point has a consequence worth knowing: a corrupted schema chunk can still
decode. A flipped bit inside a literal renames a definition or a field, and because Kiwi
messages carry field ids rather than names, the message still fits. In a sample of
single-bit flips across a real schema chunk, about a quarter decoded to a different
schema. The result is always a well-formed schema and message, never a crash, but a
consumer that needs certainty should compare the schema with one it trusts.

### Blobs

Geometry does not travel in Kiwi fields. The message's `blobs` field is an array of
`Blob { bytes }`, and a node names an entry by its `uint` index. ``FigmaBlobTable`` reads
the array (``FigmaClipboard/blobTable()``) and decodes an entry as the kind of blob the
naming field implies:

| Field | Blob | Decoded by |
|---|---|---|
| `vectorData.vectorNetworkBlob` | vector network | ``FigmaBlobTable/vectorNetwork(at:)`` |
| `derivedTextData.glyphs[].commandsBlob` | glyph outline | ``FigmaBlobTable/path(at:)`` |
| `Path.commandsBlob` (`fillGeometry`, `strokeGeometry`) | outline | ``FigmaBlobTable/path(at:)`` |

Identical glyphs share one blob, and nodes with the same network share one (P1's three
join samples name blob 1). In every capture so far — all 19 local ones, FigJam and Slides
copies included, checked by `FigmaClipboardCaptureTests` with `FIGMA_CASES` set — every
blob is named at least once and decodes as the kind its field names; an
instance's glyphs and geometry are named from `derivedSymbolData`, not the node itself.
`Message.blobBaseIndex` was never set; the table refuses a message that sets it rather than
guess how it shifts the indices. `Image.dataBlob` was never set either: a clipboard
carries image hashes, not image bytes.

Blob fields are fixed-width and little-endian — not Kiwi varints. Every count is checked
against the bytes that remain before anything is read for it, every index against what it
indexes, and every float must be finite, so a hostile blob fails with a
``FigmaBlobError`` that names the offset.

#### Vector networks

A ``FigmaVectorNetwork`` blob is a header, then the vertices, segments and regions it
counts, with nothing after:

```
header   u32 vertexCount, u32 segmentCount, u32 regionCount
vertex   u32 styleID, f32 x, f32 y                                          12 bytes
segment  u32 styleID, u32 start, f32 tangentStartX, f32 tangentStartY,
         u32 end, f32 tangentEndX, f32 tangentEndY                          28 bytes
region   u32 (styleID << 1 | nonzero), u32 loopCount,
         then per loop: u32 segmentCount, u32 segmentIndex × segmentCount
```

- **Style ids.** The word before each vertex and segment, once read as "flags", is a
  `styleID`: the key of an entry in the node's `vectorData.styleOverrideTable`, which
  carries per-vertex overrides such as `strokeCap`, `strokeJoin` and `cornerRadius`; 0 means
  no override. V1's open curves name style 3 and its table has exactly a style 3; the
  flattened donut has no table and every vertex says 0. Every segment so far says 0.
- **Regions.** The region word's low bit is the winding rule — **1 is nonzero, 0 is
  even-odd**, the reverse of the schema's `WindingRule` enum (`NONZERO = 0`, `ODD = 1`) —
  and the bits above it are the region's style id. Every captured region word is 0 or 1;
  the style-id bits are inferred, not yet seen set.
- **Loops and holes.** A region lists loops of segment indices. A donut is one region with
  two loops, the hole second; the fill rule decides what the hole does. A loop's segments
  are listed in order but each may be stored in either direction, so a walk takes each
  segment from whichever end touches the point reached so far.
- **Open loops.** A loop need not return to its first vertex. Figma writes a region even
  for an open path: V1's two-segment open curve and its single-segment line each have one
  region whose loop is the open chain. A renderer that fills such a region closes it
  implicitly; the path keeps it open so the stroke stays open.
- **Coordinates** are in the node's `vectorData.normalizedSize` space. In every fixture
  that equals the node's `size`.

``FigmaVectorNetwork/path(ofRegion:)`` walks a region's loops into a ``FigmaPath``: a
segment with both tangents zero is a line, any other is a cubic whose controls are the
start vertex plus `tangentStart` and the end vertex plus `tangentEnd` (swapped when the
segment is walked backwards), and a loop that ends where it started closes.
``FigmaVectorNetwork/segmentPath()`` draws every segment once, for strokes.

Figma's SVG export is the oracle: every V1 network, and P1's stroked samples, reproduce
the exported path within 0.01 pt once the node's translation is added, and each region's
rule matches the export's `fill-rule`. Boolean operations carry no network; their geometry
is their children's.

#### Command streams

A glyph outline or a `Path` is a stream of commands, each an opcode byte followed by its
little-endian `f32` coordinates, read to the end of the blob (``FigmaPath``):

| Opcode | Command | Coordinates |
|---|---|---|
| 0 | close | none |
| 1 | move | x, y |
| 2 | line | x, y |
| 3 | quadratic | control x, y, then x, y |
| 4 | cubic | two controls, then x, y |

Every glyph stream begins with a 0 before its first move; the decoder drops a close that
has no open subpath. A glyph with no outline is the single byte `00`: a space, and T1's
😀, whose glyph carries no outline and no `emojiCodePoints` either. Glyph coordinates are
in ems with y growing **upward** from the baseline, so a glyph draws at
`(position.x + x × fontSize, position.y − y × fontSize)` in the text node's space. Glyphs
use opcode 3 for TrueType curves and 4 for CFF ones: Inter's are all quadratics, and the
only cubics in T1 are the ten of its CJK fallback's 文. A `Path` stream has no leading 0
and is in the node's own points, y down.

Glyph outlines are decoded and tested, but text import does not need them: a text node's
content, fonts and styles come from `textData`, and a glyph blob is read only when someone
asks for its outline. Figma's SVG export of text snaps each baseline to a whole point
(`71` for T1a's `31.136`), so the oracle rounds the glyph's baseline before comparing.

## Topics

### Decoding

- ``FigmaClipboardDecoder``
- ``FigmaClipboard``
- ``FigmaDecodeError``

### The payload's parts

- ``FigmaClipboardPayload``
- ``FigmaClipboardMetadata``
- ``FigKiwiContainer``
- ``DeflateDecoder``
- ``DeflateDecodeError``

### Geometry blobs

- ``FigmaBlobTable``
- ``FigmaVectorNetwork``
- ``FigmaPath``
- ``FigmaPathCommand``
- ``FigmaPoint``
- ``FigmaWindingRule``
- ``FigmaBlobError``
