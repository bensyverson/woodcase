# `encodeForFile` vs. Pen's own headless save, for `layout-gap.pen` (2026-08-29)

Author: Claude (Fable 5), leaf `W8Rcf`. Reproduces with:

```
scripts/pen-oracle Tests/WoodcaseTests/Fixtures/layout-gap.pen \
  --out /some/scratch/dir
```

(sandbox disabled, `pen login` done once — see
[2026-08-29-pen-cli.md](2026-08-29-pen-cli.md)), then diff the scratch
`layout-gap.pen-saved.pen` against the committed
[`Fixtures/layout-gap.pen-saved.pen`](../Tests/WoodcaseTests/Fixtures/layout-gap.pen-saved.pen).

## What this checks

`layout-gap.pen` is a 2.17 fixture (one `frame`, three `rectangle` children, no
text/path/ref/component). `scripts/pen-oracle` ran it through `pen interactive`'s
headless `save()` and the result was committed unmodified as
`Fixtures/layout-gap.pen-saved.pen` — that is "what Pen itself writes for this file."
`PenCanonicalFormTests` (`Tests/WoodcaseTests/PenCanonicalFormTests.swift`) parses both
`layout-gap.pen` and that golden, runs `PenParser.encodeForFile` on the former, and
asserts every difference against the golden is one of the three named below — a new,
unnamed difference fails the test.

## The differences, and why none is eliminated

1. **`fileToken`.** Pen mints a fresh random UUID (`fileToken`) on every save;
   `encodeForFile` never generates one (`PenDocumentFileTokenTests` already pins this:
   "A fileToken is never generated"). Since the value changes on every save, no fixed
   value could ever match byte for byte — the test asserts shape (present, UUID-shaped)
   on Pen's side and absence on ours, not equality.

2. **`x: 0`, `y: 0` on root-level nodes.** `layout-gap.pen`'s root frame has no `x`/`y`
   in the source; Pen's save writes both explicitly as `0` (the value it used to lay the
   node out at the canvas root). `encodeForFile` — a flat `JSONEncoder` pass over
   `PenDocument` — omits a `nil` optional; it has no notion of "this node is a document
   root" to conditionally force a default the way Pen's own writer does. Reaching that
   in `encodeForFile` would mean threading depth/rootness through the whole `Codable`
   pipeline — not the "trivial fix" this leaf's brief allowed, so it's documented rather
   than built. This matches the pre-existing note in `GoldenParity.swift` ("Pen writes
   `x: 0`, `y: 0` explicitly where the original omitted them") and the tire-kick finding
   in `2026-08-29-pen-cli.md` ("`x: 0, y: 0` on roots") — three independent
   observations of the same behavior.

3. **Key order.** `encodeForFile` alphabetizes every object's keys (`.sortedKeys` —
   deliberately, so a migrated fixture diffs cleanly in git; see its doc comment). Pen
   writes its own fixed schema order (`type`, `id`, `x`, `y`, `name`, `width`, `height`,
   `fill`, `gap`, `children`, ...), never sorted. This is cosmetic: parsing either byte
   stream yields the same `PenDocument` once (1) and (2) above are accounted for, so
   `PenCanonicalFormTests` compares the two as parsed `PenDocument` values (which is
   inherently key-order-independent) rather than as raw bytes. It is not listed as a
   third *value* difference to eliminate — there's nothing to eliminate; it's a
   consequence of `encodeForFile`'s own documented, deliberate sort.

## One more textual difference, not covered by the test

Pen's save has **no trailing newline**; `encodeForFile` always appends one (also
deliberate — its doc comment says "ending in a newline"). Verified with
`tail -c 5 Fixtures/layout-gap.pen-saved.pen | xxd`, which ends `...36 22 0a 7d` (`"`,
`\n`, `}` — no final `\n`). `PenCanonicalFormTests` parses both files with
`PenParser.parse`, which is whitespace-insensitive, so this never surfaces there; noted
here only so a byte-level diff of the two `.pen` files isn't mistaken for a fourth
undocumented difference.

## What this pair does *not* cover

`layout-gap.pen` has no text, path, ref, or component nodes, so it never exercises the
other Pen-save normalizations `GoldenParity.swift` already catalogs from Pen.app's
desktop saves — `fontWeight: "normal"`, `fontFamily: "Inter"`, `textGrowth` defaulting,
empty-`children` dropping, `ref` flattening, `path` `width`/`height` defaulting. Those
are cross-referenced, not re-verified, by this leaf; a future `pen-oracle` run against a
fixture that exercises them would extend `PenCanonicalFormTests`'s normalizer and this
doc's difference list, not replace it.

## `layout-gap.layout.json`: regenerated, not replaced

`scripts/pen-oracle` was also run to regenerate `layout-gap.layout.json`. The values are
byte-identical to the committed fixture — same four node ids, same `x`/`y`/`width`/
`height` for each (`diff` shows only that the committed file writes each node's rect on
one line, `{ "x": 0, "y": 0, ... }`, where the regenerated file — via `python3 -m json`
— expands every key onto its own line; no numeric or key difference). The committed
file was left as-is; the layout engine's fidelity against Pen is out of this leaf's
scope.
