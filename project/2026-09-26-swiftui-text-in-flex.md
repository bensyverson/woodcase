# SwiftUI: text in flex — stacks negotiate like flexbox, except for auto text

2026-09-26, leaf `US7HZU`. **Finding: on eight boards of IBM Plex Sans text beside `fill_container` and
`fit_content` siblings, SwiftUI's `HStack`/`VStack` negotiation lands where Pen's flexbox does, within
0.1 MAE of the Core Graphics renderer on every board. The one case that diverged — `auto` text in a row
too narrow for it — was an emitter bug, now fixed: such text is `.fixedSize()`.** No board needs a
baseline in `SwiftUIRenderTests.baselines`; all eight gate at CG + 1.0.

The feasibility report ([2026-09-26-swiftui-codegen-feasibility.md](2026-09-26-swiftui-codegen-feasibility.md))
named fill/fit siblings negotiating around wrapping text as the emitter's biggest layout risk, and every
`layout-*.pen` fixture was rectangles only, so nothing exercised it.

## The boards

One top-level frame per file (the render test emits one page per fixture), in
`Tests/WoodcaseTests/Fixtures/layout-text-*.pen`, each with Pen's own PNG (scale 2) and settled layout
from `scripts/pen-oracle`. Text is IBM Plex Sans, which the test process registers
(`TestFontRegistration`) and the SwiftUI harness now loads from `Tests/WoodcaseTests/Fonts`, so the CG
side measures the real face and can act as the gate — Inter, which `render-text` uses, is not available
in-process.

MAE is 8-bit steps against Pen's PNG, from
`swift test -j 3 --filter "SwiftUIRenderTests|PenLayoutEngineTests"` (Xcode 27.0, macOS 27.0).

| Board | Case | SwiftUI MAE | CG MAE | Gate |
|---|---|---:|---:|---|
| `layout-text-fixed-width-wrap` | 180 pt fixed-width wrapping text between a fixed box and a fill box | 1.378 | 1.386 | CG + 1.0 |
| `layout-text-auto-beside-fill` | two `auto` texts either side of a fill bar | 1.615 | 1.594 | CG + 1.0 |
| `layout-text-fill-beside-fit` | fill fixed-width text beside a `fit_content` button frame | 2.167 | 2.176 | CG + 1.0 |
| `layout-text-two-fill` | two fill texts, one short, one wrapping, sharing a row | 1.283 | 1.291 | CG + 1.0 |
| `layout-text-vertical-fill` | vertical stack: auto title, fill paragraph, fill banner frame with fill text, 160 pt text | 4.314 | 4.323 | CG + 1.0 |
| `layout-text-list-row` | avatar, fill vertical column of two fill texts, auto time; `alignItems: center` | 5.014 | 4.920 | CG + 1.0 |
| `layout-text-chips` | three `fit_content` chips (padding, radius) with auto labels, then an auto text | 4.298 | 4.417 | CG + 1.0 |
| `layout-text-auto-overflow` | auto text longer than its clipped 200 pt row, beside a fill bar | 1.938 (17.180 before the fix) | 1.953 | CG + 1.0 |

The absolute figures on the three highest boards (4–5) are glyph rasterization, shared by both
renderers; the boards' sizes match Pen's exactly.

## What agrees

- **Two fills share equally.** Pen gives both fill texts in `layout-text-two-fill` 158 pt regardless of
  content (flex-basis 0). `HStack` offers equally flexible `maxWidth: .infinity` children equal shares, so
  the same split falls out with no extra code.
- **A fit sibling keeps its size; the fill text takes the rest.** `HStack` sizes its least flexible child
  first, and a padded `HStack` around an `auto` label is less flexible than a `maxWidth: .infinity` text.
- **Fixed-width text wraps and grows the row.** `.fixedSize(horizontal: false, vertical: true)` with the
  width frame reproduces Pen's line breaks and row height.

## What diverged, and the fix

`auto` text is Pen's "grows to fit; no wrapping" (the 2.17 schema). Pen lets it overflow: in
`layout-text-auto-overflow` the label is 195 pt in a 176 pt content box, and the fill bar collapses to
nothing. The emitter wrote such text with no frame, so SwiftUI treated it as a flexible view, offered it
what was left, and it **wrapped onto three lines** — a 400×156 render against Pen's 400×84, MAE 17.18.

Pen's intent is "this label never wraps", which is exactly `.fixedSize()`, so every `auto` text now ends
in it (`SwiftUINodeEmitter+Text.swift`; `render-text`'s golden gains it on five texts, its MAE is
unchanged at 3.17). This is a semantic choice, not a pixel chase: an idiomatic SwiftUI label would often
rather truncate, and a designer who wants that should say `fixed-width` in the design. It is recorded
here because it is the one place text-in-flex needed an emitter change.

## Side findings

- **`scripts/pen-oracle`'s layout was racy against Pen's web-font load.** The `Get` that writes
  `<name>.layout.json` ran before the PNG export, and on three of eight boards across four runs it measured
  text in a fallback face (19 pt lines for 14 pt Plex, and wider labels) while the PNG — which waits for
  the fonts — drew the settled layout. The script now reads the layout after the export; three further
  runs were byte-identical and every board's height matched its PNG. **Text fixtures generated with the
  old ordering may carry a fallback-font `layout.json`**; their PNGs are unaffected. Re-running the oracle
  on them is the check.
- **Medium/SemiBold Plex measures up to 2 pt narrower in-process than in Pen**; regular text matches to
  the point. The likely cause is the faces (static files in `Tests/WoodcaseTests/Fonts` against Pen's
  variable font), so `PenLayoutEngineTests.textLayoutMatchesGroundTruth` compares the text boards at a
  3.5 pt tolerance rather than the 0.5 pt the rectangle fixtures use.
- **Pen gives a starved `fill_container` a width of 1 pt**, not 0 (`layout-text-auto-overflow`'s bar,
  `tfG02`); `PenLayoutEngine` gives 0. Invisible at this size; not chased.
