# 2026-10-20 — Woodcase is Apple-platforms-only

**Ruling (Ben, 2026-10-20, Penumbra session 39): Woodcase supports macOS and iOS only.** This overrides the shared Swift rule "library packages are cross-platform by default; stay in Foundation so they build on Linux" for this repo. The override is recorded at the head of `AGENTS.md`.

## Why

- **Woodcase never built on Linux.** `Package.swift` declares only `.macOS(.v15)` and `.iOS(.v18)`. 87 files in the core `Woodcase` target import CoreGraphics, CoreText, AppKit or ImageIO with no `#if canImport` guard (counted with `grep -rlE '^import (CoreGraphics|CoreText|AppKit|ImageIO)' Sources/Woodcase`, 2026-10-20). Text measurement goes through Core Text, and layout depends on it, so no Linux build exists without replacing it.
- **There is no Linux consumer.** Penumbra (macOS), RapidPro (Metal) and the `woodcase` CLI all run on Apple platforms. A server-side renderer or CLI on Linux would revive the question; see `project/backlog.md`.
- **The rule was costing real choices.** It was why session 38 chose a pure-Swift inflate for Figma's chunk 0 over Apple's Compression framework, and why Penumbra leaf 70RuH9 kept a Linux-build criterion open that nothing here could check.

## What changes

- Apple frameworks (Compression, CoreGraphics, CoreText, ImageIO) are fair game in the core target. Figma's chunk 0 is inflated with Compression's `COMPRESSION_ZLIB` (Penumbra leaf Uip9cb).
- Code that is pure Swift and Foundation today, such as `Geometry/` and `Rendering/Mesh/`, stays that way. It is easier to test and keeps the code emitters on the renderer's own outline. It just no longer claims Linux.
- iOS stays supported: guard macOS-only APIs (AppKit, `NSFont`) as before.
- zstd stays vendored (`CZstdDecode`): Apple has no public zstd decoder.
- 70RuH9's criterion "Woodcase builds with the decoder on macOS and on Linux" is skipped.
