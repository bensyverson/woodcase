# SwiftUI line height: where the glyphs sit

2026-09-26, leaf `c9pSVy`. SwiftUI text that set a `lineHeight` sat higher than Pen's. It now sits where Pen's does,
on both deployment floors. The four `render-text-fills` boards that were baselined for it gate at CG + 1.0 again.

## How each side places a line

**Pen** follows CSS. Every line box is `lineHeight × fontSize` tall. The difference between that height and the font's
ascent plus descent is split equally above and below the glyphs (half-leading). So the first baseline sits at
`ascent + (L − ascent − descent) / 2`. The difference can be negative, which pushes the glyphs out past both edges.
On `render-text-fills-txt-lin-h-auto` (Inter Black 72, `lineHeight: 2`), Pen's glyphs stand on y = 138.0 inside a
text box at y = 40: a baseline 98.0 pt down. The formula gives 98.19.

**Core Text** with `minimumLineHeight = maximumLineHeight = L` (what `PenTextRenderer` and `PenTextMeasurer` do) gives
the same half-leading, rounded to whole points. For Inter it gives 98 (72 pt × 2), 62 (× 1), 55 (× 0.8) and 19
(14 pt × 2), against the formula's 98.19, 62.19, 55.0 and 19.09. That holds for tight lines as well as loose ones.
Helvetica and Times do **not** match the formula under Core Text (Helvetica 40 × 2: 55 against 50.8). Every fixture
uses Inter, so this was not pursued.

**SwiftUI `lineHeight(.exact(points:))`** (iOS 26 / macOS 26) makes every line box `L` tall, but puts the first
baseline exactly **one em** below the line's top, whatever `L` is. Measured for Inter at 14 and 72 pt, Helvetica 40,
Times 30 and Georgia 30, at multiples from 0.8 to 2. All the extra space lands below the glyphs. On the 72 pt board
that put them 26.2 pt above Pen's (baseline 72 against 98.2). The old baseline comment's "13 pt" was wrong: half of
the true distance.

**SwiftUI `lineSpacing`** (the pre-26 fallback) adds space only *between* lines. The first line keeps the font's own
height. Negative values are ignored.

## The fix

`penFont` wraps its text in `PenLineBox`, a `Layout` in the support file `PenSupport+LineHeight.swift`. The box reads
the text's `firstTextBaseline` from `LayoutSubview.dimensions(in:)` and places the text so that baseline lands at
Pen's. It measures the baseline instead of assuming the one-em rule, so a later SwiftUI that moves it does not
break the placement.

- **iOS 26 and later:** `.lineHeight(.exact)` inside the box. The box keeps the text's size (`n × L`).
- **Before iOS 26:** `.lineSpacing(max(0, L − natural))` inside a box `L − natural` taller. When lines are looser
  than the font's own, every line box comes out `L`. When they are tighter, only the first line does, because
  `lineSpacing` cannot pull lines closer. SwiftUI before 26 has no way to do that.

A probe that compiles the real support files renders `"HH\nHH\nHH"` at 4× and reads each baseline. On the iOS 26
branch it lands within 0.1 pt of the formula for Inter 72 × 2, 72 × 1, 14 × 2, 32 × 1.5 and 56 × 0.9. The fallback
branch was forced by patching `#available` to an unsatisfiable version. There, loose lines land within 0.9 pt by the
third line, because SwiftUI rounds the natural line up to a pixel. Tight lines are right on the first line only. The
probe lived in the session scratchpad. `SwiftUIRenderTests` renders only the iOS 26 branch on a macOS 26+ machine; it
type-checks the fallback.

## Measured

`swift test -j 3 --filter SwiftUIRenderTests`, Xcode 27.0, macOS 27.0, Inter from `~/.woodcase/fonts`. "CG" is the
test process's Core Graphics render, which has no Inter and draws a fallback face.

| board | before | after | CG |
|---|---|---|---|
| render-text-fills-txt-lin-h-auto | 8.115 | 0.030 | 4.612 |
| render-text-fills-txt-lin-v-auto | 8.115 | 0.028 | 4.353 |
| render-text-fills-txt-lin-h-fixed-left | 3.246 | 0.011 | 1.520 |
| render-text-fills-txt-lin-h-fixed-center | 3.246 | 0.011 | 0.944 |
| render-text-fills-txt-lin-h-ragged | 1.103 | 0.268 | 4.126 |
| render-text-fills-txt-lin-v-multiline | 1.513 | 0.441 | 5.906 |
| render-text (old reference / re-exported) | 3.166 / 2.566 | 2.128 | 4.575 |
| render-text-line-height-tight-wrap | 12.918 | 3.031 | 14.262 |
| render-text-line-height-loose-wrap | 8.215 | 1.831 | 6.224 |
| render-text-line-height-fixed-middle | 4.748 | 0.786 | 5.539 |
| render-text-line-height-auto-tight | 17.895 | 1.503 | 8.744 |
| render-text-line-height-stacked | 8.532 | 1.989 | 9.945 |

`render-text-line-height.pen` is new. It has five Inter boards, exported by `scripts/pen-oracle` (pen CLI, scale 2).
Only the PNGs are kept. Because this process's CG side has no Inter, its CG + 1.0 gate would pass boards that are
misplaced by 12 pt. So they sit in `SwiftUIRenderTests.ceilings`, at their measured MAE + 0.5. Every one of them
failed its ceiling before the fix. Across all five boards, the ink bands now start within 1 px (2×) of Pen's. What
is left of their MAE is glyph rasterization of large bold Inter.

## `render-text`

`render-text` is not the same problem. Its committed reference predated the 2.17 migration, which flattened the two
rich-text rows into plain strings, so Pen had drawn those rows blank. It has been re-exported (`scripts/pen-oracle
--scale 1`). Against the new reference, the row set at `lineHeight: 2` lines up to within a pixel. The remaining
2.13 has a different cause: SwiftUI's 1× `Text` is 20 pt tall for a 16 pt Inter line (19.36 rounded up), while Pen
lays that line out at 19. So each of the four 16 pt rows pushes everything below it down by 1 pt, and the board is
513 px tall against 510. Our layout engine rounds up too (`PenTextMeasurer` takes the `ceil`), so this is a
text-measurement question shared with the layout engine, not a question of line placement. The board now gates at
CG + 1.0 (limit 5.58) and its baseline is gone.
