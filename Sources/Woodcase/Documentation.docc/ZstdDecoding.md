# Decoding zstd

Decode a zstd frame from untrusted input, with a cap on what it may decode to.

## Overview

Figma's clipboard payload carries its document as a zstd frame, and no Apple API decodes
zstd. Woodcase vendors zstd's own decode-only single file, `zstddeclib.c`, as the internal
`CZstdDecode` target, and wraps it in ``ZstdDecoder``. It is vendored rather than a package
dependency on facebook/zstd, which would pull in the compressor and fetch on every fresh
build; it builds wherever Woodcase does, Linux included.

```swift
let decoder = ZstdDecoder(maxDecodedSize: 64 << 20)
let message = try decoder.decode(chunk)
```

### Trusting nothing

A clipboard can be written by anyone, so the decoder assumes its input is hostile:

- **One frame, exactly.** The input must begin with zstd's magic number and end where the
  frame ends. Anything else — another format, a skippable frame, bytes after the frame — is
  a ``ZstdDecodeError``, never skipped.
- **A cap, checked before allocating.** When the frame header declares its content size, a
  size over ``ZstdDecoder/maxDecodedSize`` is refused from the header alone. When it does
  not, the frame is streamed and refused as soon as the output passes the cap.
- **A bounded window.** A stream's window is allocated before any output, so its limit
  follows the cap: rounded up to a power of two, between 8 MiB and 128 MiB.
- **Typed errors, never garbage.** A decompressor's return code alone proves little —
  Apple's ZLIB decoder returns non-zero garbage for zstd input — so every zstd result is
  checked, a frame's checksum is verified when it has one, and the decoded size must match
  the size the header declared.

### Keeping the vendored copy current

`Sources/CZstdDecode/VENDORED.json` pins the release: its tag, the tarball's sha256 and
each vendored file's sha256. `scripts/zstd-upstream` reports a newer release or a security
advisory published since the pin, and `scripts/zstd-upstream --update` regenerates
`zstddeclib.c` from a checksum-verified release tarball and re-pins it. It needs the
network, so it runs from the release checklist rather than the commit hook. zstd's BSD
license is kept beside the vendored file.

## Topics

### Decoding

- ``ZstdDecoder``
- ``ZstdDecodeError``
