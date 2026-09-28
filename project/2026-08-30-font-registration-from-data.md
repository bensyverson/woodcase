# Google Fonts never actually registered: CoreText refuses data-backed descriptors

**2026-08-30.** Reviewing the viewer, Ben saw every text node render in SF Pro even
though the demo file asks for IBM Plex Sans, the network was up, and the font cache at
`~/Library/Caches/com.bensyverson.woodcase/fonts/` held a valid
`IBMPlexSans[wdth,wght].ttf`.

## Cause

`GoogleFontResolver.registerFont(data:)` built descriptors with
`CTFontManagerCreateFontDescriptorsFromData` and passed them to
`CTFontManagerRegisterFontDescriptors` with a `nil` registration handler. Descriptors
created from raw data carry no `kCTFontURLAttribute`, and CoreText rejects the
registration with `CTFontManagerErrorDomain` code 303 — delivered only to the handler
nobody read. Every download and cache hit succeeded; every registration silently
failed; every render fell back to SF Pro.

Reproduced by instrumenting the resolver and running
`.build/debug/woodcase render local/viewer-demo/woodcase-app.pen --output-dir $TMPDIR/render-test`:
the trace showed `cached=true`, then `register errors=[... Code=303 ...]`, then
`available('IBM Plex Sans')=false`, then the SF Pro warning.

## Why the suite never caught it

`TestFontRegistration` registers the fixture TTFs with
`CTFontManagerRegisterFontsForURL` — the file-URL API that works — so every rendering
test saw real Plex while production, registering from data, never did. The fidelity gap
between test setup and production registration is the trap; `project/gotchas.md` now
carries it.

## Fix

Registration goes through file URLs everywhere (`registerFont(at:)`, gated by
`FontRegistryGate` like every other registry call): the cached path registers the cache
file, the download path registers the file it just wrote, and the memory-fallback path
writes the bytes to a temporary file first. "Already registered" and "duplicated name"
count as success. Regression test:
`GoogleFontResolverTests.cachedFontRegistersWithCoreText`, using a vendored
`JetBrainsMono[wght].ttf` fixture (OFL) — a family no other suite registers, so a leak
from another test cannot green it.
