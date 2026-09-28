# 2026-09-26 — The MAE margin rule, and Woodcase's own thresholds audited to it

Ben's ruling (2026-09-26): "to the degree reasonable, if we're scoring well, we should bring our
MAEs in so we can catch regressions." RapidPro's MAE thresholds were tightened to this rule first
(RapidPro's `project/2026-09-26-mae-margin-rule.md`); this doc audits Woodcase's own snapshot
suites the same way. `PenInteroperability.md`'s "Snapshot Test Thresholds" section carries the
short version of the rule and `PenSnapshotTests`' own table; this doc has the full audit.

## The rule

For each MAE assertion:

1. Read the figure the suite prints today. MAE is deterministic — a loaded machine does not change
   it — but measure twice to catch a stale build or a flaky fixture.
2. Set the threshold to `max(measured × 1.5, measured + 0.25)`, rounded up to a hundredth.
3. Never make it looser than the threshold it replaces. If the formula's result is looser, keep the
   old value.
4. Where a board scores badly for a known, documented reason, keep the bar and say why beside it.
   A stale reason whose board no longer measures high is corrected in place, not carried forward
   under the old number (`PenSnapshotTests.blur2`/`blur3`: both used to carry a CoreImage-vs-web-
   renderer blur-kernel gap that no longer shows up — 0.082 and 0.174 today against ceilings of
   15.0 and 25.0).
5. A test name that spells out the threshold moves with it.
6. Record the measured figure beside the new threshold.
7. A single threshold shared across many parameterized artboards is set from the worst case, named
   in the comment; where the spread across cases is wide, converting to a per-case limit (as
   `PenShadowSnapshotTests` now does, mirroring RapidPro's `ShadowFixtureTests` for the same
   fixture) is preferred over one bar for all of them.

## Out of scope

- **`SwiftUIRenderTests.swift`** — another agent's baselines/ceilings tables were being edited at
  the same time; left untouched.
- **`WebViewRegressionTests.swift` and `ReactPaintWebViewTests.swift`** — both compare a WebKit
  render (via SleepyHollow) against Woodcase's or Pen's output, and both already feed
  `performance/mae-test.csv`, checked by `scripts/mae-check`'s own auto-updating baseline (it warns
  on any regression and always records the current run, so it already tracks drift independently
  of the hardcoded gate). Tightening their hardcoded `#expect` gates too is reasonable future work,
  but headless-WebKit renders carry real operational risk here (`.hangGuard`, `.serialized`, the
  load-sensitivity gotchas around `PageHost`/`WKWebView` — see `project/gotchas.md`), and verifying
  a tightened bound needs the same fonts the browser needs, which this pass did not want to
  entangle with a mechanical threshold sweep. Left at their current (loose) bars.
- **`PenMeshFillSnapshotTests.swift` and `PenMeshMalformedPointSnapshotTests.swift`** — already
  built to this exact convention (a `margin` constant added to each measured figure, tighter than
  this rule's own formula would ask for) by an earlier session today. Reviewed, not changed.
- **`PenTextPaintTests.swift`** — its `maeCeilings` already follow a "measured + 0.3" convention
  from when text paints landed. Re-measured (below); every ceiling is already tighter than this
  rule's formula would set it, so none change (see the table).

## Before/after

Measured with `swift test --filter <SuiteName> -j 3` (Apple M1, 2026-09-26), two runs confirming
determinism (identical measured MAEs both times). "Cap" means the margin formula would have
loosened the bar, so the old value stands unchanged.

| Test | Measured | Old | New |
|---|---:|---:|---:|
| **PenSnapshotTests** | | | |
| Shapes and fills | 0.016 | 5.0 | 0.27 |
| Gradients | 0.133 | 5.0 | 0.39 |
| Transforms and effects | 0.886 | 8.0 | 1.33 |
| Gradient extras | 0.049 | 5.0 | 0.30 |
| Strokes and paths (see the correction below the table) | 5.114 | 8.0 | 7.68 |
| Clipping and gradients | 0.060 | 5.0 | 0.31 |
| blur1 | 0.045 | 5.0 | 0.30 |
| blur2 (stale blur-kernel reason corrected) | 0.082 | 15.0 | 0.34 |
| blur3 (stale blur-kernel reason corrected) | 0.174 | 25.0 | 0.43 |
| blur2-no-bg | 0.000 | 5.0 | 0.25 |
| blur3-no-bg | 0.097 | 5.0 | 0.35 |
| **PenBankingAppTests** (shared bar; worst: day) | 3.353 | 8.0 | 5.03 |
| **PenBlurSnapshotTests** (per-artboard, worst of 1x/2x) | | | |
| flip | 0.214 | 0.5 | 0.47 |
| r8 | 0.129 | 0.5 | 0.38 |
| no-fill | 0.000 | 0.1 | 0.1 (cap) |
| layer-blur | 0.262 | 0.5 | 0.5 (cap) |
| **PenFillDomainTests** (10 cases, shared bar; worst `donut-radial`) | 0.132 | 1.0 | 0.39 |
| **PenArcDonutTests** (5 cases, shared bar; worst `three-quarter`) | 0.127 | 1.0 | 0.38 |
| **PenGradientGeometrySnapshotTests** (72 cases, shared bar; worst `rad-wide-r45-size` @1x) | 0.444 | 1.0 | 0.70 |
| **PenIconFontSnapshotTests** | 5.248 | 10.0 | 7.87 |
| **PenPerSideStrokeAlignmentTests** (26 cases, shared bar; worst `radius-outer`) | 0.027 | 1.0 | 0.28 |
| **PenTextPaintTests** (per-artboard, already tight — see Out of scope) | | | |
| txt-lin-h-fixed-left | 1.520 | 1.8 | 1.8 (cap) |
| txt-lin-v-multiline | 5.906 | 6.2 | 6.2 (cap) |
| twin-lin-h | 4.823 | 5.1 | 5.1 (cap) |
| twin-radial | 9.591 | 9.9 | 9.9 (cap) |
| twin-image-stretch | 4.887 | 5.2 | 5.2 (cap) |
| icon-grad | 1.659 | 1.9 | 1.9 (cap) |
| **PenViewBoxSnapshotTests** | 0.015 | 5.0 | 0.27 |
| **PenStrokeFillTests** (25 cases, shared bar; worst `ellipse-lin-h-outer`) | 0.071 | 1.0 | 0.33 |
| **PenShadowSnapshotTests** (converted to per-artboard, worst of 1x/2x) | | | |
| inner-under-stroke | 0.145 | 0.75 | 0.40 |
| inner-under-child | 0.398 | 0.75 | 0.65 |
| outer-and-inner | 0.260 | 0.75 | 0.52 |
| inner-ellipse | 0.212 | 0.75 | 0.47 |
| two-outer | 0.455 | 0.75 | 0.71 |
| outer-translucent | 0.406 | 0.75 | 0.66 |
| outer-frame-children | 0.464 | 0.75 | 0.72 |
| **PenWoodcaseAppTests** | | | |
| Home Collection | 2.025 | 3 | 3 (cap) |
| Usage Log | 2.897 | 4 | 4 (cap) |
| Ratings | 2.459 | 4 | 3.69 |
| Wishlist | 2.430 | 4 | 3.65 |
| Home Collection (Dark) | 1.957 | 3 | 2.94 |
| Usage Log (Dark) | 2.624 | 4 | 3.94 |
| Ratings (Dark) | 2.342 | 4 | 3.52 |
| Wishlist (Dark) | 2.294 | 4 | 3.45 |
| Settings | 1.354 | 3 | 2.04 |
| Settings (Dark) | 1.362 | 3 | 2.05 |
| Settings Compact | 1.354 | 3 | 2.04 |
| Settings Compact (Dark) | 1.361 | 3 | 2.05 |
| Lab | 0.595 | 2 | 0.90 |
| Lab (Dark) | 0.705 | 2 | 1.06 |
| **SlotOverrideKeysSnapshotTests** (22 cases, shared bar; worst `bare-injected-replace`) | 0.077 | 0.5 | 0.33 |

> **Corrected 2026-09-26 (leaf `WBOels`):** Strokes and paths' 5.114 was a stale reference, not a
> renderer gap. `render-strokes-and-paths.png` was exported on 2026-03-23 by an older Pen that drew
> a `path` with its geometry left at its SVG offset (scaled to the box, not moved to its origin), so
> the three chevrons sat 12×13.3 pt low and right and the star 3.2 pt right. Today's Pen draws the
> committed 2.17 file and the 2.9 original identically (0.000 MAE between the two exports), and
> that export differs from the old one by 5.108 — the whole of both renderers' error. Re-exported
> with `scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-strokes-and-paths.pen` (pen CLI
> 0.3.9); CG now measures 0.027 and SwiftUI 0.034 (`swift test -j 3 --filter
> 'PenSnapshotTests/strokesAndPaths|SwiftUIRenderTests'`), and the bar is 0.28.
>
> **Corrected 2026-09-26 (leaf `hwCwvs`):** the text rows above were measured in a fallback face —
> the test process had no Inter — and with Core Text's own natural line height, which sets Inter at
> 16 pt one point taller than Pen. With Inter committed as a test font and text set at Pen's
> rounded line height (`PenTextMeasurer.naturalLineHeight(of:)`), re-measured with
> `swift test --filter "PenBankingAppTests|PenWoodcaseAppTests|PenTextPaintTests" -j 3`:
> PenBankingAppTests 3.209 (worst: night) → 4.82; PenTextPaintTests `txt-lin-h-fixed-left` 0.692
> → 1.04, `txt-lin-v-multiline` 3.591 → 5.39, `twin-lin-h` 3.318 → 4.98, `twin-radial` 6.575 →
> 9.87, `twin-image-stretch` 3.644 → 5.2 (cap), `icon-grad` 1.659 → 1.9 (cap);
> PenWoodcaseAppTests Usage Log 2.054 → 3.09, Ratings 2.014 → 3.03, Usage Log (Dark) 1.979 →
> 2.97, Ratings (Dark) 1.885 → 2.83. The other rows did not move.
>
> **Corrected 2026-09-27 (leaf `HVBKsf`):** most of the text rows' remaining error was not glyph
> rasterisation but two measurable mismatches: Core Text moved Inter's `opsz` axis to the point
> size (Pen draws its default, 14), and it placed lines under an explicit `lineHeight` with all the
> leading on one side. With both fixed, re-measured with
> `swift test -j 3 --filter "PenBankingAppTests|PenWoodcaseAppTests|PenTextPaintTests"`:
> PenBankingAppTests 0.891 (worst: night) → 1.34; PenTextPaintTests `txt-lin-h-fixed-left` 0.008
> → 0.26, `txt-lin-v-multiline` 0.029 → 0.28, `twin-lin-h` 0.074 → 0.33, `twin-radial` 0.085 →
> 0.34, `twin-image-stretch` 0.051 → 0.31, `icon-grad` 1.659 → 1.9 (cap); PenWoodcaseAppTests
> Home Collection 1.928 → 2.90, Usage Log 1.779 → 2.67, Ratings 1.581 → 2.38, Wishlist 2.390 →
> 3.59, the dark four 1.855 → 2.79, 1.702 → 2.56, 1.461 → 2.20, 2.252 → 3.38, the four Settings
> screens 1.250–1.252 → 1.88. Lab and Lab (Dark) did not move.

38 threshold sites (covering ~217 individual parameterized test cases) reviewed; every one now
sits within the margin above its measured figure, or is capped at an already-tighter bar. Verified
by `swift test --filter "PenSnapshotTests|PenBankingAppTests|PenBlurSnapshotTests|PenFillDomainTests|PenArcDonutTests|PenGradientGeometrySnapshotTests|PenIconFontSnapshotTests|PenPerSideStrokeAlignmentTests|PenTextPaintTests|PenViewBoxSnapshotTests|PenStrokeFillTests|PenShadowSnapshotTests|PenWoodcaseAppTests|SlotOverrideKeysSnapshotTests" -j 3` — 62 tests, 14 suites, two consecutive green runs with identical measured MAEs.
