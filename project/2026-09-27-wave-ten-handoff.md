# 2026-09-27 — Handoff, wave ten: React against Pen, groups, RapidPro catch-up, incremental settling

The tenth integrator session, following [wave nine](2026-09-27-wave-nine-handoff.md). Start with `job orient`,
then this doc. Seven Woodcase and RapidPro agents ran (five at a time, `-j 3`, all Opus except one Sonnet); every one answered the
brief-errors question, and every commit went through a full `swift test -j 3 --quiet` over the combined tree
before it was pushed. The only failure all wave was `ActivityCommandTests` "--follow stops when the process that
launched it goes away" — in three of five full runs (the last two passed), never alone — now filed as `55P02C`.

## What landed

| Commit | Leaf | What |
|---|---|---|
| `7d8814c` | `oiUTFr` | Budgets re-measured with nothing building (load 7–24): every `woodcase-app` row faster (`tree` 271.7 → 156.4 ms, `shot` 246.7 → 148.9 ms); the synthetic `tree` row failed its 400 ms measured ceiling once, so it is 500 ms (~1.3×). **The `set` verb (175.9 ms / 200) is the tightest committed budget.** Script write-then-read pair 201 → 143 ms release |
| `5546fc0` + RapidPro `baa8ea0` | `6fu79C`, `SdtjDG`, `WJHlhu` | Public `PenGlyphPaint`, `PenGlyphOutlines`, `PenIconGlyph`; RapidPro's mirrors deleted. RapidPro draws the atlas upright (glyphs within 0.003 px of CG, were 0.55 px low) and paints text/icon gradient, image and stacked fills through the glyph outlines; its text/icon ceilings tightened to 0.25–0.46 |
| `02d3373` | `50MfO5`, `SctC0l`, `hPsLl7` | React: centered box strokes straddle the edge (two box-shadows), lines center on their y, arcs and rings come from CG's own outline (`PenShapeOutline.svgPathData`), center/outer per-side strokes use the overlay; a dropped Tailwind `gap` (the real "lines as one bar" bug); default stroke width 1; stroke shadow before effect shadows |
| `a8b50162` | `cqBw2i`, `INL8Zi` | **Groups settle at their children's true union (anchor excluded)** and turn/flip about the anchor like every other free node; `PenTransformBuilder` has no group exception any more; CG, SwiftUI (`PenGroupFlow`), `tree` and the viewer follow; `absoluteRects` composes turned parents. New Pen-oracle fixture `render-free-groups.pen`. **Breaking** for anything that copied the old group rule (RapidPro fixed below; Penumbra `zzxHpw` noted) |
| RapidPro `2fa42ca` | `Nlcuwt`, `F2LywA` | RapidPro places every node as `PenRenderer.enter` does, through `unturnedBox` + `PenTransformBuilder`; flips reach children (`RenderTransform.composed(with:)`); turned text/paths rasterize at the unturned box. `txt-rotated` 5.6 → 0.09, free-groups 2–89 → ≤0.085. Root `iDXenh` closed |
| `d6ad90b` | `Gmh2sB`, `0M8jRo`, `3Xbv46`, `RgeMUN` | React text: `fontOpticalSizing: none`, Pen's natural pitch in px at generate time (`normal` when the font is unknown), `white-space` pre/pre-wrap by Pen's wrap rule, JSX-safe newlines, vertical alignment. Effects on every node kind in Pen's order (text-shadow, drop-shadow filters, one filter key, blended box shadows as layers). `render-text` 28.4 → 1.5; sweep 141 → 151 boards at CG + 1.0 |
| `18d745b` | `VtOM4W` | React off-axis linear (corner-keyword tile), angular (sampled conic) and turned radial (SVG data URL) gradients at Pen's geometry; 29 boards 4.3–60.4 → 0.09–0.26, all at CG + 1.0. Shared math in `GradientGeometry+Screen.swift` |
| `7975d7b` | `QP5E24` | SwiftUI reads themed numbers in effects, rotation (runtime trig for the stack frame), gradient stops and per-side widths. `render-themed-numbers.pen` has its own batch: the shared SwiftUI render batch holds only one themed fixture |
| `d859a51` | `Tdgxuz` | **Incremental settling.** A settled tree is kept per root, keyed by `revision(of:)` (subtree + every component drawn, now including slot content and replacement nodes — a bug fixed on the way); anything no revision covers (theme, variables, axes, imports, fonts, read context, font generation) re-lays every root. `TextSizeCache` per run, tied to the font generation; `RootOverlap.Baseline` shares it across the five writing verbs' before/after checks. Release, interleaved: **write+read pair 169.9 → 16.1 ms** (100 pairs 17 s → 1.6 s), **`set` verb 171.3 → 125.4 ms**. `IncrementalSettleEquivalenceTests`: every fixture × 8 writes equals a fresh settle |

## Ben's rulings this session

- **`Jg0BOv`:** match Pen — a `layout: none` frame with no size settles at 0×0 (children still draw, no flow
  space, stroke and shadow still paint), plus a lint warning. Recorded on the leaf; **ready to build**.
- **Pause after this wave** to save context; handoff here.

## Two-way decisions made unattended

- The synthetic `tree` measured ceiling moved 400 → 500 ms (the rule its sibling ceilings follow).
- `0M8jRo` closed with its blend-mode criterion partial: CSS cannot blend one entry of a shadow list, so only a
  CSS box's outer shadows keep their blend (as layers); other blended shadows warn. An SVG-filter group
  silhouette matched Pen almost exactly but WebKit's filter regions were fragile; it is parked in the leaf note.
- React's natural pitch is measured on the generating machine's fonts (the leaf asked for exactly that); the
  golden suites register the test fonts first.

## Still open

- **Fidelity (`LxFb4C`):** `Jg0BOv` (ruled, build it); `BpaSrF` which Plex face Pen draws (run it alone — it
  moves many gates; `layout-text-vertical-fill` already passes CG + 1.0 and waits for it).
- **React worklist (`dSwsw3`):** `MY1B1R` frame sizing fallbacks and fitted columns; `3n7gRZ` mesh raster at 2x.
  Also not covered: angular gradients on SVG shapes/strokes, inner per-side borders shift children, a line with
  no stroke draws `currentColor`.
- **Issues:** `0IegsD` font registration bumps the generation even when nothing registered (defeats incremental settling for any document declaring `fonts` — highest-value next perf fix); `nxLzvE` `effectiveRefData` spends minutes on some fixture with instances expanded; `55P02C` the `--follow` orphan test (fails most loaded full runs — fix at the source);
  `8xg1Mt` JS-global names; `rkYhcz` layout carries the unturned size (`unturnedBox` is now the one seam to swap);
  `6vLFNQ` Material glyph shapes.

  > **Correction (2026-09-27, `nxLzvE`):** the cause above was wrong. No fixture is slow as authored;
  > the equivalence test's `moveToAnotherRoot` write put instances inside their own components, and the
  > expanded tree walk had no cycle rule, so it never ended — `effectiveRefData` only ran on every row of
  > it. See [2026-09-27-expanded-tree-cost.md](2026-09-27-expanded-tree-cost.md).
- **Penumbra:** not started this wave either. First step: build against Woodcase and RapidPro main. Expect
  breaks from wave nine and ten (`RenderTextContent.color` → `ink`, group placement, `PenGlyphPaint`).
  `zzxHpw` carries a note on the new group rule.

## Traps hit this session

- **Two agents touching one baselines file conflict at merge**, as expected; resolve by keeping each side's
  entries and re-running the React suites on the merged tree before committing (both goldens and baselines can
  pass on each branch and not together).
- **Tell a running agent when main moves under its files** (`SendMessage`, "merge main at your next pause") —
  reacttext and swiftui both merged cleanly that way instead of conflicting at integration.
- **A RapidPro agent needs a Woodcase snapshot, not the main checkout**: the integrator's staged squashes in the
  main checkout would otherwise break its builds. A detached `git worktree add --detach` beside it works.
