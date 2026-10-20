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
