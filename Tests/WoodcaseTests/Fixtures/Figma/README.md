# Figma clipboard fixtures

Synthetic Figma clipboard payloads for the Kiwi reader and the Figma importer. Every case
was authored for these tests in a scratch Figma file by Penumbra's fixture plugin
(`scripts/figma-fixtures/`); none comes from client work. The case matrix, the fixture
policy and the format findings are in Penumbra's
`project/2026-10-19-figma-interchange.md` (§3, §6).

## Layout

- `schema.kiwi` — the Kiwi schema, raw-inflated from the first chunk. Every case carries
  the same 76,411-byte schema (fig-kiwi versions 101 and 106 alike), so it is stored once.
- `<case>/message.kiwi` — the case's message, zstd-decoded from the second chunk.
- `<case>/clipboard.html` — the whole `text/html` clipboard payload, for V1 and M1a only,
  to test extraction end to end.
- `<case>/reference.svg`, `<case>/reference-2x.png` — Figma's own export of the selection,
  a geometry and appearance oracle (an SVG's viewBox includes any drop-shadow offset).
- `<case>/manifest.json` — what the case exercises, its counts and node types, its
  fig-kiwi version, and the SHA-256 of each file.
- `SHA256SUMS` — every file above.

## Redaction

Each capture named its Figma file: the file key appears in figmeta and, as a
null-terminated Kiwi string, in the message (`pasteFileKey`). It is replaced in place by
`FixtureFileKey00000000`, the same length, so no other byte of a message moves. In the two
`clipboard.html` files the message chunk was compressed again with the `zstd` CLI, so its
compressed bytes are zstd's rather than Figma's; the decoded message is identical.

## Rebuilding

From Penumbra, with the gitignored captures in `local/figma-cases/` and the `zstd` CLI
on `PATH`:

```sh
scripts/figma-curate --out ../Woodcase/Tests/WoodcaseTests/Fixtures/Figma
```
