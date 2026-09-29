# 2026-09-28 — The faces Pen draws: IBM Plex Sans, and every family in Pen's Google table

Leaf `BpaSrF` (fidelity gaps, F12). **Pen draws IBM Plex Sans from Google's variable face**
(`wdth` 75–100, `wght` 100–700) as fonts.gstatic.com serves it at v23, and the suites now
register that file in place of the static `IBMPlexSans-{Regular,Medium,SemiBold}.ttf`.

The premise the leaf was filed on — "the test IBM Plex Sans glyphs differ from Pen's" — was
only half right. The static cuts are an older release (3.005 against 3.201), but they draw the
same design at the same advances; what made the CG and SwiftUI renders of the Plex boards
score 1.3–4.9 was that **Woodcase resolved a static family's weights one step light**: CSS 500
drew the Regular cut and 600 drew the Medium (finding 1, since fixed). The variable face sidesteps that —
each weight is set on the `wght` axis — so the swap moved the CG renders of the five Plex boards
with Medium or SemiBold text from 1.59–4.92 to 0.55–1.82, left the three set only in Regular
where they were, and WebKit, which picked the static cuts correctly by their `@font-face` weights,
moved by at most 0.08.

**Three findings came out of it, and the same leaf fixed them** (*The three findings*, below):
a static family's weight now resolves to the cut CSS font matching picks, in the renderer and
in the emitted SwiftUI; the React page puts each text's first baseline on the whole point Pen
does, which took the `layout-text-*` boards from 1.8–4.4 to 0.80–1.50 and moved every WebView
gate down; and a squeezed `fill_container` keeps Pen's 1-pt floor. The WebKit gap was not the
font, as the first round of this note had left open.

A second pass, at Ben's request, audited Pen's whole bundled Google table (1,899 families)
against what Woodcase's Google font resolver picks: the resolver's file selection agrees with
Pen for every family both know; the rest is google/fonts' main branch having moved on from
Pen's pinned catalog (see *Every family*).

## How the face was established

1. **Pen's font source.** Pen's editor JavaScript in
   `/Applications/Pen.app/Contents/Resources/app.asar` carries its Google font catalog as a
   literal table. IBM Plex Sans has two styles, both variable:
   `https://fonts.gstatic.com/s/ibmplexsans/v23/zYXgKVElMYYaJe8bpLHnCwDKtdbUFI5NadY.ttf`
   (weight 400, axes `wdth` 75–100, `wght` 100–700) and `.../zYX-KVElMYYaJe8bpLHnCwDKhdTeEKxIedbzDw.ttf`
   (the italic). Found with `LC_ALL=C grep -a -o '{name:"IBM Plex Sans",styles:.\{600\}' app.asar`;
   `scripts/pen-font-table.py` prints the whole table as JSON.
2. **The file.** The gstatic v23 file (sha1 `3bd98f63…`, 532,740 bytes) is what is committed as
   `Tests/WoodcaseTests/Fonts/IBMPlexSans[wdth,wght].ttf`, with its OFL license staying in
   `LICENSES/ibm-plex-sans-LICENSE`. The Google font resolver's copy from the google/fonts
   repository (`~/.woodcase/fonts/ibmplexsans/IBMPlexSans[wdth,wght].ttf`, sha1 `105e2a89…`) is
   the same release, Version 3.201: gstatic's is subset by four glyphs (`IJacute`, `Jacute` and
   their lower cases), and every one of the 891 codepoints both map has the same advance at
   `wght` 400, 500 and 600, the same outline and the same `gvar` deltas
   (`scripts/font-advance-diff.py <gstatic.ttf> <github.ttf>`, fontTools 4.62.1).
3. **The static cuts are the same design.** They are Version 3.005. Their advances match the
   variable face's instances for every ASCII character at 400, for all but 28 at 500 (by 1–2
   units per 1000 em) and all but 8 at 600; their ASCII glyph bounds match within 4 units.
4. **Widths cannot tell the faces apart.** Every auto-width Plex text in the `layout-text-*`
   fixtures set in either face rounds up to the width Pen's layout gives it: 10 of 10 for both
   (`swift scripts/plex-face-widths.swift <variable.ttf> <static-dir>`; the static cuts are at
   `git show 674f1ff:Tests/WoodcaseTests/Fonts/IBMPlexSans-Medium.ttf` and its siblings). So
   the Pen export's evidence is its pixels, below.
5. **Pen's exports, A/B.** With nothing changed but the test font, against Pen's own 2x exports:
   the boards set only in 400 did not move (CG `layout-text-two-fill` 1.291 → 1.297,
   `fixed-width-wrap` 1.386 → 1.382, `auto-overflow` 1.953 → 1.956); every board with Medium or
   SemiBold text fell (`chips` 4.417 → 0.754, `list-row` 4.920 → 1.773, `vertical-fill`
   4.323 → 1.752), and in layout 17 text-board rects that had sat 1–3 pt from Pen's now match
   (below). WebKit — the React harness — loads each face by `@font-face` and moved by at most
   0.075. The design is the same; the weight Woodcase drew was not.
6. **Why the static weights drew light** (reproduced by hand: register the three static cuts,
   ask Core Text for family "IBM Plex Sans" with `PenTextMeasurer.mapWeight`'s trait):
   `mapWeight` gives 500 the trait 0.1 and 600 the trait 0.2, but the Medium cut reports 0.2
   and the SemiBold 0.3, so Core Text answers 500 with `IBMPlexSans` (Regular) and 600 with
   `IBMPlexSans-Medm`. See finding 1.

## Every family: `scripts/pen-font-audit`

`scripts/pen-font-audit > audit.tsv` (sandbox off) extracts Pen's table, then decides each
family's files with the resolver's own code — `GoogleFontCache.directoryName(for:)`,
`GoogleFontMetadata.parse` and `entry(weight:style:)`, compiled in from `Sources/` — against a
blobless, sparse google/fonts checkout holding only its METADATA.pb files (made on first use in
`local/google-fonts`). It downloads no font. Run on 2026-09-28, Pen's table against google/fonts
`23e54b5` (2026-09-24):

| Verdict | Families |
|---|---:|
| Agree (same kind — static or variable — same axes, every style Pen offers answered by its own file) | 1,874 (518 variable) |
| Not found under the resolver's directory name | 18 |
| Variable in google/fonts where Pen draws a static cut | 6 |
| Both variable, different axes | 1 |
| Static where Pen draws variable; a weight or italic answered by another face | 0 |
| **Total in Pen's table** | **1,899** (529 variable) |

None of the 25 disagreements is the resolver choosing badly among the files google/fonts has:

- **Not found (18).** Nine are Material Icons and Material Symbols, which google/fonts does not
  host; Woodcase draws those from its bundled icon fonts, not the resolver. The other nine were
  renamed or replaced in google/fonts after Pen's catalog was cut: `BBH Sans Bartle`, `Bogle`
  and `Hegarty` are `BBH Bartle`… there now, and the six `Edu … Cursive/Hand/Hand Pre` families
  became `Edu AU VIC WA NT Hand`, `Edu QLD Beginner` and their siblings.
- **Variable for static (6)** — Capriola, Castoro, Grenze, Libre Baskerville, Libre Caslon Text,
  Noto Sans Myanmar: google/fonts' main branch ships only a variable file now, where Pen's pinned
  catalog still serves the static cuts. There is no static file to pick.
- **Axes (1)** — Akshar: google/fonts added a `CTRS` axis beside `wght` 300–700.

So the only disagreement is **catalog drift**: Pen pins each family to a fonts.gstatic.com
version (`v23` for IBM Plex Sans, `v20` for Inter) from its bundled table, and the resolver reads
google/fonts' main branch. For the families the suites draw it is nil: IBM Plex Sans, Inter
(upright and italic), IBM Plex Mono, Spectral, Lora and Instrument Serif — seven files — were
each fetched from gstatic at Pen's version and compared with the google/fonts file — the same
version string, and not one advance differs across 9,472 shared codepoints (`scripts/font-advance-diff.py`,
at `wght` 400–700 for the variable faces); gstatic's files are subsets by up to 34 glyphs.

**Recommendation (for Ben; not built).** Keep reading google/fonts. Switching the resolver's
source to Pen's gstatic URLs would buy exact version parity for 16 of 1,899 families (the six
static-for-variable, Akshar, the nine renames) and would tie Woodcase to a table baked into
Pen's app build, which it cannot read at run time without Pen installed. The cheaper hedge, if
the renames ever matter to a user: teach the resolver the nine old names (an alias table), and
rerun this audit when Pen's catalog or google/fonts moves.

## Gates moved

Before: `swift test -j 3` on `674f1ff` (static cuts). After: the same with the variable face, run
twice (the moved suites again with `--filter "WebViewRegressionTests|PenWoodcaseAppTests|SwiftUIScreenRenderTests|ReactRenderWebViewTests|PerformanceTreeBudgetTests"`),
identical figures both times. The moved lines are listed by
`scripts/mae-log-diff.py <before.log> <after.log>`. New limits follow the margin rule where the
suite uses it — `max(measured × 1.5, measured + 0.25)`, rounded up to a hundredth, never looser
(`PenInteroperability.md` § *The margin rule*; `project/2026-09-26-mae-margin-rule.md`) — and
each suite's own convention otherwise (a baseline + 0.5).

**`PenLayoutEngineTests` — text-in-flex boards.** Tolerance 3.5 pt on every rect → the exact
0.5 pt every other layout fixture uses, except `tfG02` (finding 3) at 1.5. Measured with the
tolerance at 0: 17 rects off by 1–3 pt before (`tfE01` `Vertical stack` 112 vs 114, `tfH07`
x 283 vs 286), 1 after (`tfG02`, width 0 vs 1).

**`PenWoodcaseAppTests` (CG vs Pen), margin rule.**

| Screen | Before | After | Old limit | New limit |
|---|---:|---:|---:|---:|
| home-collection | 1.920 | 0.859 | 2.90 | 1.29 |
| home-collection-dark | 1.849 | 0.890 | 2.79 | 1.34 |
| usage-log | 1.771 | 0.698 | 2.67 | 1.05 |
| usage-log-dark | 1.697 | 0.732 | 2.56 | 1.10 |
| ratings | 1.560 | 1.065 | 2.38 | 1.60 |
| ratings-dark | 1.444 | 0.983 | 2.20 | 1.48 |
| wishlist | 2.381 | 1.805 | 3.59 | 2.71 |
| wishlist-dark | 2.244 | 1.671 | 3.38 | 2.51 |
| settings | 1.243 | 0.445 | 1.88 | 0.70 |
| settings-dark | 1.246 | 0.472 | 1.88 | 0.73 |
| settings-compact | 1.242 | 0.444 | 1.88 | 0.70 |
| settings-compact-dark | 1.246 | 0.472 | 1.88 | 0.73 |
| lab | 0.595 | 0.526 | 0.90 | 0.79 |
| lab-dark | 0.705 | 0.639 | 1.06 | 0.96 |

**`WebViewRegressionTests` (CG vs the React page), margin rule.**

| Component | Before | After | Old limit | New limit |
|---|---:|---:|---:|---:|
| StatCard | 3.625 | 3.212 | 5.5 | 4.82 |
| ActionButton | 0.501 | 0.433 | 0.76 | 0.69 |
| FavoriteCard | 1.995 | 1.454 | 3.0 | 2.19 |
| TabBar | 0.892 | 0.840 | 1.45 | 1.26 |
| PencilListItem | 2.066 | 1.577 | 3.13 | 2.37 |
| TextInput | 0.726 | 0.576 | 4.2 | 0.87 |
| StatusBar | 0.228 | 0.217 | 0.48 | 0.47 |
| home-collection screen | 1.753 | 0.832 | 3.17 | 1.25 |
| settings screen | 1.303 | 0.598 | 4.11 | 0.90 |
| lab screen | 0.488 | 0.422 | 5.39 | 0.68 |
| ratings screen | 1.362 | 0.703 | 3.46 | 1.06 |

**`SwiftUIScreenRenderTests` baselines (limit = baseline + 0.5).** home-collection 1.939 → 0.875,
-dark 1.853 → 0.896; usage-log 1.767 → 0.692, -dark 1.678 → 0.715; ratings 1.545 → 1.048,
-dark 1.409 → 0.950; wishlist 2.400 → 1.822, -dark 2.240 → 1.668; settings 1.216 → 0.412,
-dark 1.220 → 0.443; settings-compact 1.216 → 0.412, -dark 1.219 → 0.443; lab 1.723 → 1.669,
-dark 2.144 → 2.103. The generated SwiftUI resolves static weights with the same trait scale
(`PenSupport.swift`'s `traitWeight`), so its Plex screens were one weight light too.

**`SwiftUIRenderTests` `layout-text-*` (limit = CG + 1.0, set by CG's own figure).** SwiftUI
before → after (CG): auto-beside-fill 1.592 → 0.549 (0.553), chips 4.414 → 0.750 (0.754),
fill-beside-fit 2.167 → 1.806 (1.816), list-row 4.909 → 1.760 (1.773), vertical-fill
4.314 → 1.741 (1.752); auto-overflow 1.941, fixed-width-wrap 1.374 and two-fill 1.289 unmoved.
No constant changes: each limit fell with CG's figure, by up to 3.15.

**`ReactRenderWebViewTests` `layout-text-*` baselines (limit = baseline + 0.5).** React before →
after: auto-overflow 4.377 → 4.374, fill-beside-fit 4.051 → 4.053, fixed-width-wrap
2.861 → 2.859, two-fill 2.976 → 2.976, vertical-fill 3.610 → 3.685; and three boards that had
gated at CG + 1.0 only against the light CG render now fail it and are baselined:
auto-beside-fill 1.825 (CG 1.594 → 0.553), chips 3.441 (CG 4.417 → 0.754), list-row 3.740
(CG 4.920 → 1.773). The `Gap` they carry, `plexGlyphs` ("the test IBM Plex Sans glyphs differ
from Pen's"), was a wrong cause and became `plexText` (finding 2).

> **Corrected (second round, same leaf):** finding 2 found the cause — the first baseline, a
> device pixel off Pen's whole point — and fixed it; `plexText` is gone, seven of these boards
> are ceilings or gate at CG + 1.0, and `chips` is baselined for its own drift (`autoTextWidth`).

## The three findings

Found in the first round and closed on the same leaf and branch. Figures below are
`swift test -j 3` (full, unfiltered), before against after, diffed with
`scripts/mae-log-diff.py`.

### 1. A static family's Medium drew Regular — fixed

`PenTextMeasurer.mapWeight` (and `traitWeight` in the emitted SwiftUI's `PenSupport.swift`)
turned CSS 500 into the Core Text weight trait 0.1 and 600 into 0.2, and Core Text matched the
nearest cut. But the traits differ from family to family — IBM Plex Sans reports its Medium at
0.2 and its SemiBold at 0.3, Avenir Next and Helvetica Neue a Medium at 0.23 — so 500 drew
Regular, 600 Medium, and in the emitted SwiftUI even 700 drew SemiBold (the template's own
table put 700 at 0.3). No fixed table of traits can be right.

**Fix.** ``PenFaceMatching`` (`Sources/Woodcase/PenFaceMatching.swift`) picks the cut the way CSS
font matching does (CSS Fonts 4 §5.2): each cut's weight is its OS/2 `usWeightClass` — the
number a `@font-face` declares — and the rule is exact, else for 400–500 the heavier up to
500, then lighter, then heavier; below 400 lighter then heavier; above 500 heavier then lighter.
Normal-width cuts come first (CSS matches `font-stretch` before weight) and cuts of the asked-for
slant before the others. The renderer's static branch uses it, and `mapWeight` is gone. The
emitted SwiftUI carries the same rule as a CoreText-only template,
`PenSupport+FaceMatching.swift`, which `PenFontFace.ctFont` calls.

**Test family.** No committed static family has a Medium or a SemiBold, and a system family's
cuts vary from machine to machine, so the tests use **Woodcase Static Sans**: Inter cut at 400,
500, 600 and 700, subset to ASCII and renamed (Inter's OFL reserves no font name; Plex, Lora
and JetBrains Mono do), written by `scripts/gen-static-test-family.py` into
`Tests/WoodcaseTests/Fonts/StaticSans/` (18 KB a cut). Core Text reports its cuts at 0, 0.2, 0.3
and 0.4 — the same traits as the static Plex cuts — so it reproduces the bug exactly.
`PenFaceMatchingTests` holds the rule (10 cases) and eight weights of the family (450, 500,
`medium`, 550, 600, `semibold`, 700, `bold`), all red before; `SwiftUIFaceMatchingTemplateTests`
compiles the support templates with a probe `main.swift` (`xcrun swiftc`, as the SwiftUI render
batch does) and checks five weights, red before (500 drew Regular, 600 Medium, 700 SemiBold).

**Gates.** None moved: no fixture sets a static family at a weight the old table got wrong
(`render-font-faces` draws IBM Plex Mono and Spectral at 400 and 700 only, and the Plex boards
draw the variable face since the first round). The fix is covered by the two suites above.

### 2. WebKit set every text a device pixel off Pen's baseline — fixed

The first round said WebKit set IBM Plex Sans unlike Pen, and that the font was not the cause.
Measured per text node (each text's rect cropped from Pen's export and WebKit's capture, and
the vertical shift that aligns them found): **every Plex text sat exactly one device pixel low**
at 12, 13, 14 and 18 pt, CG exact, and the ink the same (14.9 against 14.9 on `chips`) — so not
weight, not width. Inter showed it too, both ways by size: +1 px at 13–16 pt, −1 at 18–20, 0 at
12, 24, 28, 32 (`text-natural-line-height`, which scores low only because its text covers little of
the board). One model predicts all of them: CSS puts the first baseline at
`ascent + (line-height − ascent − descent) / 2` (hhea metrics) and WebKit snaps that to a device
pixel; Pen puts it on a whole point (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)`` —
the rounded ascent on a natural line). IBM Plex Sans at 13 pt on its 17 pt line is 13.375, 27 px
at 2x against Pen's 26; Inter at 16 pt is 15.32 against 16.

Ruled out on the way, as the integrator suggested: optical sizing and variation settings (the
page already writes `font-optical-sizing: none`; ink and advances match), weight synthesis (ink
equal), the `wdth` default (widths match Pen's layout), letter spacing and horizontal placement
(only `chips` has a horizontal residue, below).

**Fix.** ``ReactEmitter``'s `textLayoutStyles` writes, on a top-aligned text whose font the
emitter knows (the same condition as the natural pitch), the difference as a margin pair:
`marginTop: -0.375, marginBottom: 0.375`. It moves the element without changing its margin box,
so its place in a flex or block flow is unchanged, and it adds no stacking context, as
`position: relative` or a `transform` would (text is never absolutely positioned itself: a free
child's wrapper is). Middle and bottom alignment are left alone: where Pen rounds their baseline
is not measured. `ReactEmitterTextBaselineTests` (natural line up, natural line down, a set line
height), red before; the eight component goldens gained 77 margin pairs (±0.25 or ±0.5, read).

**What is left.** `layout-text-chips` keeps 2.638 (CG 0.754): its error grows along the row of
chips (1 at the first, 6–7 at the last) and the board aligns best one device pixel right, which
fits Pen rounding each auto-width label's width up to a whole point while CSS keeps it
fractional. Not measured further; baselined as `autoTextWidth`. An explicit `lineHeight` is
still written as a multiple, so CSS's pitch is unrounded where Pen rounds it: the first
baseline is corrected, later lines of a wrapped text can drift by the rounding.

**Gates** (before → after; limits by each suite's rule):

| Suite | Board | Before | After (CG) | Gate now |
|---|---|---:|---:|---|
| `ReactRenderWebViewTests` | layout-text-auto-beside-fill | 1.825 | 1.060 (0.553) | CG + 1.0 (was baselined) |
| | layout-text-auto-overflow | 4.374 | 1.201 (1.956) | ceiling (was baselined) |
| | layout-text-chips | 3.441 | 2.638 (0.754) | baseline `autoTextWidth` |
| | layout-text-fill-beside-fit | 4.053 | 1.503 (1.816) | ceiling (was baselined) |
| | layout-text-fixed-width-wrap | 2.859 | 0.964 (1.382) | ceiling (was baselined) |
| | layout-text-list-row | 3.740 | 1.304 (1.773) | ceiling (was baselined) |
| | layout-text-two-fill | 2.976 | 0.801 (1.297) | ceiling (was baselined) |
| | layout-text-vertical-fill | 3.685 | 1.230 (1.752) | ceiling (was baselined) |
| | render-text | 1.470 | 0.791 (0.885) | ceiling (was CG + 1.0) |
| | render-text-line-height-auto-tight | 1.641 | 0.703 (0.939) | ceiling |
| | render-text-line-height-loose-wrap | 1.591 | 0.747 (1.053) | ceiling |
| | render-text-line-height-stacked | 1.466 | 0.779 (1.272) | ceiling |
| | render-text-line-height-tight-wrap | 2.370 | 0.963 (1.574) | ceiling |
| | render-rotated-free-rtxts | 0.167 | 0.101 (0.140) | ceiling |
| | render-rotated-free-rtxtf, -rtxta | 0.091 | 0.084 (0.144) | ceiling 0.091 → 0.084 |
| | text-natural-line-height | 0.195 | 0.072 (0.209) | ceiling 0.195 → 0.072 |
| | render-text-shadows-text-inner | 5.741 | 5.094 | baseline |
| | -text-inner-soft | 3.367 | 3.024 | baseline |
| | -text-inner-wrap | 4.565 | 3.842 | baseline |
| | -text-inner-translucent | 7.444 | 7.358 | baseline |
| `ReactUnfilledPaintWebViewTests` | control, bad-hex, missing-variable | 0.530 | 0.328 | 0.80 → 0.58 |
| | disabled-then-solid | 0.528 | 0.327 | 0.80 → 0.58 |
| `ReactIconPaintWebViewTests` | gradient | 0.408 | 0.267 | 3.19 → 0.52 |
| | image | 0.377 | 0.271 | 2.97 → 0.53 |

A ceiling holds a board to its own MAE + 0.5, capped at CG + 1.0; a baseline to its MAE + 0.5.
`WebViewRegressionTests` compares CG with the React page, so it moved too (margin rule):

| Component | Before | After | Limit |
|---|---:|---:|---:|
| StatCard | 3.212 | 3.037 | 4.82 → 4.56 |
| ActionButton | 0.433 | 0.209 | 0.69 → 0.46 |
| FavoriteCard | 1.454 | 0.829 | 2.19 → 1.25 |
| TabBar | 0.840 | 0.605 | 1.26 → 0.91 |
| PencilListItem | 1.577 | 1.156 | 2.37 → 1.74 |
| TextInput | 0.576 | 0.219 | 0.87 → 0.47 |
| StatusBar | 0.217 | 0.070 | 0.47 → 0.32 |
| home-collection screen | 0.832 | 0.614 | 1.25 → 0.93 |
| settings screen | 0.598 | 0.406 | 0.90 → 0.66 |
| lab screen | 0.422 | 0.328 | 0.68 → 0.58 |
| ratings screen | 0.703 | 0.547 | 1.06 → 0.83 |

### 3. A squeezed `fill_container` is 1 pt in Pen — fixed

`layout-text-auto-overflow`'s `fill-bar` (`tfG02`) was 0 wide in Woodcase and 1 in Pen. A probe
of Pen's engine, now the fixture `flex-fill-squeeze.pen` with its `pen-oracle` layout (2026-09-28),
gives every `fill_container` 1 pt on the main axis whenever its siblings and gaps leave it less:
overflowed by 27 or 132, room used exactly, 0.5 left, a frame fill, a vertical fill, two fills
side by side (1 each, the second placed after the first's point). A second probe put fills in a
`fit_content` parent: Pen sizes the parent without them (0 wide, or the fixed siblings' extent)
and still gives each fill 1 pt, overflowing it — which Woodcase's order of work already does
once the floor is there.

**Fix.** `PenLayoutEngine.FlexLayout.minimumFillMain = 1`, the floor of the fill share
(`PenLayoutEngine+FlexFill.swift`). `PenFlexFillMinimumTests` holds all 12 fill rects of the
probe to Pen's, red before. `PenLayoutEngineTests`' text boards no longer need an exception for
`tfG02`: every rect is at the exact tolerance. The linter's `fill-in-fit-parent` message said
such a fill "resolves to 0"; it now says it gets Pen's 1-pt floor and overflows its parent, and
`clipped` reports the same node, as it overflows in Pen too (`DocumentLinterTests` updated, and
<doc:WoodcaseLint>). The emitted React (`flex-1`) and SwiftUI (`minWidth: 0`) still give such a
fill 0; not changed here.
