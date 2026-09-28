# 2026-09-28 — Handoff, wave twelve: the geometry model, React and SwiftUI effects, the orphan test

The twelfth integrator session, following [wave eleven](2026-09-27-wave-eleven-handoff.md). Start with `job orient`
(it lands on `BpaSrF`, which carries a note pointing here), then this doc. Seven Woodcase agents ran to completion
(at most five at once, `-j 3`; six Opus, one Sonnet). Every merge went through a full `swift test -j 3` on the combined
tree before it was pushed; the only failures were WebKit `__READY__` timeouts under load, each re-run alone and
passing, and one real test race fixed at integration (below).

## What landed

| Commit | Leaf | What |
|---|---|---|
| `1057820` | `w2er6i` | **[The geometry model](2026-09-28-geometry-model.md)**: from Pen's own code and a pen-oracle probe, strokes, shadows and blur never enter Pen's layout (turned nodes included, even with `layoutIncludeStroke`); a parent allocates the bounds of the turned box. Three named extents proposed; Ben ruled (below). `scripts/gen-geometry-probe`, `scripts/layout-diff` |
| `8bad5d0` | `jBvokK` | `followStopsWhenOrphaned`: two holes in the *test* — its wait never looked after its deadline, and its launcher gave up silently after 30 s (a follower slow to start under load took itself for one born orphaned). `PollingWait`, exit 3 for a follower that never printed, and failure diagnostics (ps, stderr, `sample`). No failure caught with the diagnostics in, so neither hole is proven the one that fired |
| `4c2411a` | `vPZ0ia` | SwiftUI casts a node's outer shadow from its stroke band as well as its shape (`PenSilhouette`, `penDropShadow(outset:)`); new Pen-oracle fixture `render-stroke-shadows.pen`: 4.4–14.1 → 0.08–0.16 |
| `59a7c28` | `Mu4JsL`, `AyTAji` | React: turned fixed-size flex child's slot by margins (35.8 → 0.63); angular gradients on SVG shapes and strokes as conic `foreignObject`s (18–24 → ~0.1; 5–9 → ~0.05); inner per-side strokes via the overlay, children unmoved (→ 0.000); unstroked line draws nothing; outer stroke as a spread box-shadow, shadows spread by the stroke's reach; Material Symbols imported from the per-weight path, 200 by default (2.95 → 0.41). Text and group inner shadows warn at generate time (Ben's ruling). Four new Pen-oracle fixtures, `scripts/gen-react-gap-fixtures` |
| `deab418` | `YrLTHN` | A turned `fill_container` flex child fills its unturned box and takes its turned bounds as its slot, both axes (`PenLayoutEngine+FlexFill.swift`). Pen's first-pass artefact kept as a documented divergence (PenInteroperability's new **Kept Divergences**). `scripts/pen-settle` writes Pen's first and settled layouts. Also fixed a race in `PenIconFontRegistryTests` "libraries is sorted" (two reads of the shared registry) |
| `eda68ad` | `Wkr2Pd` | `PenPlacement` + `placement(of:rect:layoutRects:)` / `canvasPlacement`; `paintedExtent` / `canvasPaintedExtent` (Pen's `getVisualLocalBounds`, every probe export size to the pixel); `shot --extent painted`; render-test helper placing Pen's references by the painted extent |
| `39b49fc` | `B7M4na` | CG casts no outer shadow from a line (2.52 / 4.57 → 0.006 / 0.000); SwiftUI casts an even-odd shadow from an unstroked even-odd shape |
| RapidPro `c5f3a13` | — | Shared agent-rules refresh; `.jobs/local.json` and `.jobs.db*` ignored as in Woodcase |

## Ben's rulings this session

- **Geometry model (2026-09-28):** adopt the three extents — (i) bounds = `PenRect`, unchanged; (ii) placement = box +
  transform (`PenPlacement`); (iii) painted extent, never an input to layout. Keep `PenRect` bounds-first; do not
  reshape it.
- **Pen's first-pass layout artefact:** keep Woodcase's settled layout; document the divergence.
- **Penumbra selection matches Pen:** hit the turned box first, then the stroke band — not the axis-aligned bounds.
- **Penumbra gets a job root** (`LZOYtB`, issue kind); RapidPro got one on the same footing (`ispmO6`).
- **RapidPro rules drift:** commit it (done, `c5f3a13`).
- **Pause after this wave** to save context.

## Still open

- **`BpaSrF`** (last leaf of `LxFb4C`, **run alone** — it moves many gates): Pen draws IBM Plex Sans from Google's
  **variable** face — its bundled font table lists only `ibmplexsans/v23/…ttf` (wdth 75–100, wght 100–700) and its
  italic (evidence on the leaf). Swap the suites' static `IBMPlexSans-{Regular,Medium,SemiBold}.ttf` for the variable
  face (OFL), confirm against an export's glyph widths, re-measure and tighten every affected gate (`.plexGlyphs`
  baselines in `ReactRenderWebViewTests+Baselines.swift`, `layout-text-*` in CG/SwiftUI), before/after recorded.
- **`ozlazY`** React and SwiftUI give a turned `fill_container` child its turned slot (React's turned-slot margins
  cover fixed sizes only; SwiftUI's `rotatedFrame` likewise). Render references must come from Pen's **settled**
  layout (`scripts/pen-settle`).
- **RapidPro `3Jg2Xd`** culling reads `paintedExtent`; also make RapidPro's shadow silhouette cast nothing from a line.
- **Penumbra `hhcyOb` + `Fs6Aeo`** (one agent): drag through `canvasTransform`/`PenPlacement`; selection hits the
  turned quad, then the stroke band (`paintedExtent` + stroke path). Both now unblocked by `Wkr2Pd`.
- Not filed, from agent reports: React draws no inner shadow on icons or SVG shapes and does not warn; a painted stroke
  on a full-width line still draws `currentColor`; `warnUnblendedShadows` can double-warn with the new inner-shadow
  warnings; `shot --extent painted` does not round its frame to whole pixels as Pen's export does (298 vs 299 px on
  one probe); `ShotCommand.swift` is 450 lines.

## Traps hit this session

- **pen-oracle's layout is Pen's first pass, not its settled layout** (gotcha 2026-09-28). Use `scripts/pen-settle`
  before pinning any turned-in-flex expectation to Pen.
- **A fixture named `layout-*.pen` joins the SwiftUI golden set** (gotcha 2026-09-28).
- **An agent can be stopped by permission checks that give no verdict** (gotcha 2026-09-28): the React agent stopped
  with its code done; the integrator finished its loose ends.
- **Briefs were wrong usefully again:** "inner shadow over the stroke" was inverted (Pen draws it under, and React
  already did); the Material package has no weight prop (weight is the import path); the 0×0 stroke band rule holds on
  every box; "CG as the reference for lines" was wrong (Pen casts no line shadow). Keep asking question 7.
