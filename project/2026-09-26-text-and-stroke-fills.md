# Non-solid paints on text and strokes: what Pen does, what Woodcase does (2026-09-26)

Author: Claude (Opus 5.5), leaf `NXgRKl` under `b3HCbu`, for Ben. Research only; no source, test or fixture changed.
Ruling that prompted it (Ben, 2026-09-26): non-solid fills on text and strokes come into scope, linear gradients on
text first, once we know exactly what Pen does.

Evidence is in `local/NXgRKl-fills/` (gitignored): the fixture, its generator, Pen's reference renders at 1x and 2x,
Woodcase's renders, the analysis scripts and their outputs. Every figure below names the script that reproduces it.
All behavior is established from Pen's **outputs** — PNG and PDF exports, its re-saved `.pen`, and its HTML export —
never from its source.

## Findings first

1. **Pen paints text with every fill type, and the paint's domain is the text node's box.** Linear, radial and
   angular gradients, image fills (stretch, fill, fit), mesh gradients, shader fills, stacked fills, fill opacity and
   fill blend modes all render on text. The paint is laid out over the node's layout rectangle, exactly as it would be
   on a rectangle of the same size, then shown only where glyphs are. It is **not** the glyph-ink bounds and **not**
   per line: a three-line vertical gradient runs once, top to bottom, across the whole box, and every line of ragged
   left-aligned text shares one horizontal ramp (finding 3 has the numbers).
2. **Pen paints strokes with every fill type, and the domain is the node's box, whatever the alignment.** For
   rectangles, ellipses, paths and frames (uniform and per-side widths), inner, center and outer strokes all place
   stop 0 and stop 1 on the node's layout edges, never on the stroke outline's edges. Outside that box a gradient
   **pads** (keeps its end color), while an image is **decal** (draws nothing): an outer stroke painted with an
   image in `stretch` or `fit` mode is invisible, and in `fill` mode only the part overlapping the covered image
   rectangle shows. A shader is evaluated in node-box coordinates, `@resolution` = node size.
3. **Measured domains** (Pen 2x renders, `python3 analyze.py pen text-and-stroke-fills 2` and
   `analyze_clamped.py`; box = Pen's own settled rect from `text-and-stroke-fills.layout.json`):

   | Case | Node box on the axis | Fitted stop 0 → stop 1 | RMS |
   |---|---|---|---|
   | text, fixed-width 480, `"MM"` left-aligned | x 40 → 520 | 39.98 → 519.96 | 0.62 pt |
   | text, same, centered | x 40 → 520 | 40.05 → 519.94 | 0.40 pt |
   | text, fixed-width-height 480×300, one line at top | y 40 → 340 | 40.01 → 339.95 | 0.39 pt |
   | text, same, `textAlignVertical: middle` | y 40 → 340 | 40.01 → 339.98 | 0.25 pt |
   | text, 3 wrapped lines, vertical gradient | y 40 → 298 | 40.11 → 298.10 (each line alone: the same) | 0.26 pt |
   | text, ragged lines 4/2/1 glyphs, horizontal | x 40 → 380 | 40.01 → 379.99 (each line alone: the same) | 0.36 pt |
   | text, auto width, lineHeight 2, vertical | y 40 → 184 | 39.99 → 184.01 | 0.12 pt |
   | text, auto width, horizontal | x 40 → **389** | 40.00 → **385.00** | 0.39 pt |
   | icon (lucide star) 120×120 | x 40 → 160 | 40.00 → 160.00 | — |
   | rect stroke 16, inner / center / outer | x 60 → 260 | 60.01→260.00 / 59.99→260.01 / 60.00→260.00 | ≤ 0.25 pt |
   | rect stroke 16 outer, vertical | y 60 → 180 | 59.99 → 179.98 | 0.13 pt |
   | ellipse stroke 16 outer | x 60 → 260 | 60.00 → 260.00 | 0.23 pt |
   | path (zig-zag) stroke 12 center | x 60 → 260 | 60.00 → 260.00 | 0.22 pt |
   | frame, per-side widths 4/16/24/8 | x 60 → 260 | 60.00 → 260.00 | 0.23 pt |
   | UV image, stretch, on rect/ellipse/path/per-side strokes | node box | u 60.4→259.6, v 60.5→179.5 (path: →159.5) | ≤ 0.23 pt |
   | UV image, `fill` mode, outer stroke | aspect-fill of the box: x 40 → 280 | u 40.45 → 279.48 | 0.27 pt |
   | shader (u = x/res, v = y/res), center stroke 24 | node box | u 59.99 → 260.01, v 180.00 → 60.00 (GL y-up) | 0.22 pt |

   The one exception is **auto-width text on the horizontal axis**: the domain starts at the box's left edge but is
   1–7 pt narrower than the width Pen reports for the node (`autoprobe/auto.pen`: 140→138, 194→192, 294→287,
   399→395 with `letterSpacing: 10`, 327→326). It is not the glyph-ink extent either. Open question 1.
4. **Pen strips strokes, underline and strikethrough from text nodes.** Loading a file drops `stroke`,
   `strokeWidth` and `strokeAlignment` from every `text` node, and `Insert` drops them from a new one. An `Update`
   keeps them, and `save()` even writes them to disk, but the next load drops them again, and a render after that load draws no stroke. `underline: true` and
   `strikethrough: true` are dropped the same way and draw nothing, although both keys are in the 2.19 schema
   Pen itself publishes (`cli039-schema.txt:144,149`). Reproduce with `probe-text-props.pen` (commands in the
   appendix). So there is no "stroke on text" case to implement.

   > **Confirmed in Pen.app 1.2.14 (2026-09-26, leaf `rjt7to`).** The app strips all three on load, saves none,
   > and its export draws none; see [what Pen drops from a file](2026-09-26-what-pen-drops-from-a-file.md).
   > `woodcase lint` now reports each as `text-style-stripped`.
5. **Per-side stroke widths honor `strokeAlignment`, and the default is center** — a bug in Woodcase for solid
   strokes as much as for gradients. A frame with widths top 4, right 16, bottom 24, left 8, measured on the 2x
   export (`perside/perside.pen`):

   | Alignment | Pen left / right / top / bottom bands | Woodcase |
   |---|---|---|
   | (unset = center) | x 56–64, 252–268; y 58–62, 168–192 | x 60–68, 244–260; y 60–64, 156–180 (inner) |
   | inner | x 60–68, 244–260; y 60–64, 156–180 | same — matches |
   | outer | x 52–60, 260–276; y 56–60, 180–204 | inner again |

   `PenStrokeRenderer.swift:80-84` says per-side strokes are "always inner … matching CSS/Pen border behavior";
   that documented reason is wrong. Pen's own HTML export agrees with its renders: it emits the per-side stroke as a
   `border` with negative margins of half each width, i.e. centered.

   > **Fixed 2026-09-26 (leaf `yKT5m9`).** Woodcase now honors the alignment on frames, rectangles and browser
   > nodes, rounded corners included; see [the follow-up](2026-09-26-gradient-geometry-and-per-side-strokes.md).
6. **Stacking, opacity and blend behave on text and strokes exactly as on shapes.** Twins (a 400×120 text box above a
   400×120 rectangle with identical fills) show the same colors at the same relative positions for
   `["#00FF00", gradient@0.5]`, `[gradient, "#FFFFFF80"]`, gradient `opacity: 0.4` and `blendMode: multiply` over a
   solid. Each fill is composited through the glyph coverage separately: in the multiply twin, the glyph edges keep a
   faint green fringe where the rectangle (pixel-aligned edges) has none. A clip-per-fill implementation reproduces
   that; flattening the fills first and painting once would not.
7. **The paint rotates with the node.** A text node with `rotation: -20` carries its horizontal ramp along the rotated
   baseline (`txt-rotated`), consistent with the domain being the node's own box in its own coordinate space.
8. **Pen's HTML export** (`Export(ids, "html-css" | "html-tailwind", …)`, `html/export-css.html`):
   - **Text:** `background-clip: text; -webkit-background-clip: text; -webkit-text-fill-color: transparent;
     color: transparent` with the paint as `background-image`, `background-size: 100% 100%`, `no-repeat` — the box
     domain again. Stacks become `background-color` plus `background-image` layers; fill opacity is baked into
     stop alphas; image fills become `url()` with `cover`/`contain`; mesh and shader fills are rasterized into a
     `data:image/webp` background. **Blend modes are dropped** (the multiply twin exports as a plain stack).
     Tailwind mode keeps the same declarations in an inline `style`.
   - **Uniform strokes:** an absolutely positioned `<svg>` over the node box. The stroke outline is pre-expanded into a
     filled path, filled with a `linearGradient`/`radialGradient` in `userSpaceOnUse` spanning the node box (e.g.
     `x1=0 x2=200` on a 200-wide rect); inner and outer alignment are a `<mask>` with or without the shape.
   - **Per-side strokes:** `border-image: linear-gradient(…) 1` with `border-width: 4px 16px 24px 8px`,
     `box-sizing: content-box` and negative margins. Its domain is the border box, not the node box — a small
     infidelity in Pen's own export.
   - **Lossy cases:** image, mesh and shader strokes export as an **empty div** (the stroke disappears); a stacked
     stroke keeps only its **top** layer; the icon's gradient becomes an SVG `linearGradient` over the glyph's view box.
   - **An angle bug:** the linear gradient on the two *auto-sized* text nodes exported as `linear-gradient(0deg, …)`
     for rotations 270 and 180 alike, while the identical paint on a fixed-size text box exported as `90deg`. Don't
     copy Pen's export blindly.
9. **Pen's PDF export keeps gradient text and gradient strokes as vector shadings** (`pdf/export.pdf`: three
   `/ShadingType` entries and embedded fonts for one gradient text, one gradient rect, one gradient stroke).
10. **Woodcase today** draws none of this; see the table and the code references below. Its renders differ from Pen's
    by MAE 2.6–29 on these cases, and the numbers are dominated by *what is missing* (the text is drawn black on black,
    the stroke is not drawn).

## Engine and tooling

- **`pen` CLI 0.3.9** (`/opt/homebrew/lib/node_modules/@pen.dev/cli/package.json`), headless
  `pen interactive --in/--out`, sandbox off. It saves `"version": "2.19"`, its `read_skill({path:"pen-schema.md"})`
  declares `version: "2.19"` and the `Browser` node, and `get_app_state()` reports the integrated browser — the
  1.2.14 app's feature set. So the brief's worry that the CLI runs the older 2.17 engine (true of 0.3.5, see
  `2026-09-26-pen-1.2.14-compatibility.md` finding 12) no longer holds. I did **not** drive Pen.app 1.2.14 to confirm
  pixel parity; finding 4 is the one I would confirm there first (open question 2).
- **Reference renders:** `scripts/pen-oracle local/NXgRKl-fills/text-and-stroke-fills.pen --out local/NXgRKl-fills/pen --scale 1,2`
  (8 s for 50 artboards × 2 scales). It also writes Pen's settled layout and its canonical re-save.
- **Woodcase renders:** `.build/debug/woodcase shot text-and-stroke-fills.pen <artboard> --scale {1,2} --out wc/…`,
  the main checkout's debug build of 2026-09-26 09:12 (HEAD was `2912b68`), sandbox off.
- **MAE:** `scripts/` has no standalone comparer (`mae-check` only diffs suite output against a baseline), so
  `local/NXgRKl-fills/mae.py <pen dir> <wc dir> <prefix>` re-implements
  `PenSnapshotTestHelpers.meanAbsoluteError` exactly: 8-bit sRGB premultiplied RGBA, crop to the overlap, sum of
  absolute channel differences including alpha over `w·h·4`.

## The fixture

`local/NXgRKl-fills/text-and-stroke-fills.pen`, generated by `make_fixture.py` (which also writes `uv.png` and
`uv.frag`). 50 artboards, each a black, clipped, `layout: "none"` frame, so an export is exactly the frame and the
paint can be read back per pixel:

- **Measurement paints.** A red→blue linear ramp (rotation 270 = left→right, 180 = top→bottom): on a fully covered
  pixel `R + B = 255`, so `t = B/255` is the ramp parameter and a least-squares fit of position against `t` gives
  where stops 0 and 1 sit. A **UV image** (256×128, R = u·255, G = v·255) does the same for image fills in two axes,
  and a **UV shader** (`gl_FragColor = vec4(gl_FragCoord.xy / u_resolution, 0, 1)`) for shader fills.
- **Text domain probes (`txt-*`)**: auto width; fixed width with left and center alignment; wrapped and hard-broken
  multi-line; fixed width and height with top and middle vertical alignment; rotated; underline/strikethrough.
- **Twins (`twin-*`)**: fixed-size text over a same-size rectangle with the same fill(s) — linear, rotated linear with
  center/size, radial, angular, image stretch/fill/fit, mesh, shader, two stacks, multiply blend, fill opacity.
- **Strokes (`stk-*`)**: rectangle inner/center/outer with ramp and UV; UV `fill`/`fit` outer; radial, angular,
  mesh, shader, stacked, multiply and opacity strokes; a stroke over a solid fill; ellipse; open zig-zag path;
  frames with per-side widths (with and without corner radius).
- **Text strokes (`txt-stroke-*`)** and **icon gradient (`icon-grad`)**.

For committing, split it by surface — `render-text-fills.pen` (the `txt-*` and `twin-*` boards, icon) and
`render-stroke-fills.pen` (the `stk-*` boards plus `perside/perside.pen`'s three boards) — with `pen-oracle` 2x
PNGs beside each. Drop `txt-stroke-*` and `txt-underline` from the committed set or keep them only as lint fixtures,
since Pen strips those keys (finding 4). Contact sheets: `sheet-pen-{text,twin,stk}.png` and `sheet-wc-*.png`.

## What Woodcase does today

| Surface | Code | Behavior |
|---|---|---|
| Text rendering | `PenTextRenderer.swift:164-168`, `:199-231` | One `kCTForegroundColorAttributeName`, the **last** enabled solid fill; gradient, image, mesh and shader fills are skipped, and with no solid fill the text is black. Stacked translucent solids collapse to the top one; fill `blendMode` is ignored. |
| Icon rendering | `PenIconFontRenderer.swift:60` | Same `extractColor` — a gradient icon is black. |
| Text stroke | `PenRenderer.swift:491-492` | `TextData` is `PenStrokable` (`PenNode+TextData.swift:11`), but the renderer never strokes text. That happens to match Pen. |
| Underline / strikethrough | `PenTextRenderer.swift:174-180`, `:90-136`; `ReactEmitter+Text.swift:62-63` | Drawn and emitted. Pen strips and does not draw them (finding 4). |
| Shape strokes | `PenStrokeRenderer.swift:14`, `:132-149` | The **first** enabled solid in `stroke` only; gradients, images, mesh, shader skipped; stacks collapse to one color; `blendMode` on a color stroke ignored. |
| Per-side strokes | `PenStrokeRenderer.swift:16-28`, `:80-130` | Always inner, whatever `strokeAlignment` says (finding 5). |
| Shape fills (the reusable part) | `PenFillRenderer.swift:10-66`, `:142-183` | Draws every fill type except mesh and shader; the gradient/image **domain is `path.boundingBox`** (`:79`, `:152`), which equals the node box for shapes — but would be the glyph-ink box for a glyph outline, the wrong domain. |
| Even-odd shape fills | `PenRenderer.swift:592-625` | Solid fills only: a donut ellipse or even-odd path with a gradient fill draws nothing. Not in the brief; same fix shape. |
| React text | `ReactEmitter+Text.swift:23-28`, `ReactEmitter+Styles.swift:174-178` | `color:` from the **first** enabled fill if it is solid; a gradient first fill emits no color at all (the text inherits). Note: the CG renderer takes the *last* solid and the emitter the *first* — they disagree on a stack. |
| React strokes | `ReactEmitter+Styles.swift:417-455`; `ReactEmitter+Shapes.swift:79`, `:259` | `emitFillValueRaw(paint.all.first)`: first fill, solid only; uniform stroke → inset `box-shadow` or `outline`, per-side → `border*`; SVG shapes get `stroke="<color>"`. A gradient stroke emits nothing. |
| Lint | `Sources/Woodcase/Lint/` | Nothing about paints: no warning for a paint Woodcase cannot draw, nor for keys Pen strips from text. |
| Schema help | `woodcase help schema text` | Advertises `stroke*`, `underline`, `strikethrough` on text. |

> **Fixed 2026-09-26 (leaf `EL9llT`): the "Shape fills" and "Even-odd shape fills" rows.** `PenFillRenderer` now takes a
> clip (path + fill rule) and a domain (the node box) separately, and even-odd outlines draw every fill type. The row's
> claim that `path.boundingBox` "equals the node box for shapes" was only true of rectangles, frames and full ellipses:
> Pen uses the box on polygons, arcs, curves and `viewBox` paths too, where the bounding box differed. See
> [the follow-up](2026-09-26-fill-clip-and-domain.md).

> **Fixed 2026-09-26 (leaf `OxFPIT`): the "Text rendering" and "Icon rendering" rows.** Text and icons now take every
> paint `PenFillRenderer` draws, through the union of their glyph outlines over the node's box; a lone solid still goes
> to `CTFrameDraw` and renders byte-identically (every `Tests/WoodcaseTests/Fixtures/*.pen` rendered with `woodcase
> render --scale 1` and `--scale 2` before and after: 808 PNGs, all identical except `render-text.pen`, whose
> `middle-vertical` node stacks two solids and so now composites both). The fixture is committed as
> `render-text-fills.pen` (the `txt-*` boards, the twins except mesh and shader, and `icon-grad`) with Pen's 2x exports.
> Stacks and blends are no longer collapsed to the last solid.

> **Fixed 2026-09-26 (leaf `D3TIGo`): the "Shape strokes" row.** Strokes now draw every paint `PenFillRenderer`
> draws — stacks, opacity and blend included — clipped to the stroke's outline and laid out over the node box, for
> every alignment, uniform and per-side; an outer `stretch`/`fit` image stroke draws nothing, as in Pen. See
> [the follow-up](2026-09-26-stroke-paints.md).

> **Fixed 2026-09-26 (leaves `LCDPXr`, `kKIf7C`): the "React text" and "React strokes" rows.** Painted text is a
> `background-clip: text` stack over the text's box; a painted box stroke is a masked overlay whose padding box is the
> node's box, and an SVG stroke a `userSpaceOnUse` paint server. Rendered in WebKit (`swift test --filter
> ReactPaintWebViewTests`), the emitted React matches Pen's 2x exports within MAE 0.16 on fifteen stroke boards, and
> ramps land within 0.35 pt of the node box on stroke and fixed-width text boards. Details and limits in
> `PenCodeGen.md` ("Paints on text", "Paints on strokes").

**Measured today** (`python3 mae.py pen wc text-and-stroke-fills`, full `mae-woodcase-today.txt`). The boards are
mostly black, which dilutes whole-board MAE, so the twin rows also give the text half alone:

| Case | MAE @1x | MAE @2x | Note |
|---|---|---|---|
| txt-lin-h-auto / -v-auto | 6.68 / 6.68 | 6.67 / 6.66 | text drawn black |
| txt-lin-v-multiline | 8.82 | 8.80 | |
| twin-lin-h (text half @2x) | 7.20 | 7.21 (14.32) | rect half 0.10 |
| twin-radial (text half) | 14.37 | 14.37 (28.64) | rect half 0.10 |
| twin-image-stretch (text half) | 6.83 | 6.86 (13.66) | rect half 0.07 |
| twin-lin-diag | 20.06 | 20.08 | **rect half 11.53** |
| twin-angular | 13.36 | 13.37 | **rect half 12.42** |
| twin-mesh / twin-shader | 48.94 / 25.63 | 48.96 / 25.65 | neither half drawn |
| stk-rect-lin-h inner / center / outer | 7.65 / 8.50 / 9.35 | same | stroke not drawn |
| stk-rect-radial-center | 25.50 | 25.50 | |
| stk-rect-stack | 6.37 | 6.37 | solid red layer only |
| stk-frame-perside-lin-h | 7.04 | 7.04 | |
| stk-rect-uv-outer / -fit-outer | 0.00 / 0.00 | 0.00 / 0.00 | Pen draws nothing either (decal) |

Two things this table says beyond "not implemented":

- **The shape gradient mapping itself is off for rotated linear gradients with a center/size, and for angular
  gradients** (rect halves 11.53 and 12.42, where the axis-aligned linear, radial and image rects are ≤ 0.10). Text
  and strokes will inherit whatever `PenFillRenderer` does, so this is worth fixing first or alongside. It is outside
  this leaf's question and I did not diagnose it.

  > **Diagnosed and fixed 2026-09-26 (leaf `UoumNa`).** Pen lays every gradient out in the node's normalized box
  > (rotation and size applied in the unit square before it is stretched to the box); Woodcase worked in pixel space.
  > See [the follow-up](2026-09-26-gradient-geometry-and-per-side-strokes.md).
- **MAE is a poor criterion for text paints, because text layout already differs.** For the same `Inter` 900 72 pt
  `"MMMMM"`, Woodcase settles the auto-width box at 333 pt and Pen at 349 pt; the glyph run for 96 pt `"MMMM"` spans
  x 43.5–390.5 in Woodcase against 44.5–402 in Pen. Solid **white** text on the twin board already scores MAE 19.8 on
  its text half at 2x (`pen-cov/` against `wc-cov/`). A projection of a box-domain implementation — Woodcase's own
  glyph coverage times Pen's paint for the box (`projected.py`, output `mae-projected.txt`) — lands at 6.6 for the
  linear twin, 13.2 for radial, 7.3 for image stretch: better than today, and bounded by the glyph mismatch, not the
  paint. Criteria for text should therefore be **geometric** — the fitted domain, as `analyze.py` does it — plus an MAE
  measured *relative to the same text in a solid color*, not an absolute threshold.

## How a CoreGraphics implementation would work

**One refactor underneath both:** split what `PenFillRenderer` clips to from what it maps the paint over. Today
`renderFills(_:path:in:imageProvider:)` does both with one `CGPath` (`path.boundingBox` is the domain). Give it an
explicit domain, e.g. `renderFills(_ fills: PenFills?, clip: CGPath, fillRule: CGPathFillRule, domain: CGRect, in:
imageProvider:)`, with shapes passing their node rect. Each fill then does: save, clip (anti-aliased), set the fill's
blend mode and alpha, draw the paint over the domain (gradients with `drawsBefore/AfterStartLocation` to pad; images
into their fit/fill/stretch rectangle computed from the domain, which is naturally decal), restore. Finding 6 wants
exactly this per-fill clip. The even-odd path (`PenRenderer.swift:592`) folds into the same call via `fillRule`,
which also gives donut ellipses their gradients for free.

**Text.** Keep today's `CTFrameDraw` path when the fills are a single enabled solid color, so no existing text MAE
fixture moves. Otherwise:

1. Build the same `CTFrame` (same framesetter, frame path and vertical offset, so **text measurement is unchanged**).
2. Collect the glyph outlines: for each line and run, `CTRunGetGlyphs`/`CTRunGetPositions`, `CTFontCreatePathForGlyph`
   with a transform to the line origin plus glyph position, flipped into the node's y-down space; union into one
   `CGMutablePath`. `CGContext.setTextDrawingMode(.clip)` + `CTFrameDraw` is the shorter alternative, but an explicit
   path is reusable (inner shadow on text, hit-testing, PDF) and testable.
3. `PenFillRenderer.renderFills(fills, clip: glyphPath, fillRule: .winding, domain: node rect)`.

Pitfalls: glyphs without outlines (emoji and other bitmap-font glyphs) return `nil` from `CTFontCreatePathForGlyph` —
fall back to drawing that run with the text clip mode, or with its last solid color; the domain for **auto-width**
text is 1–7 pt narrower than the box in Pen (open question 1); cache the glyph path per node for the viewer's
repaint loop (a paragraph is a few hundred glyph paths); underline/strikethrough need no gradient support if Ben
confirms Pen drops them. **PDF** stays vector because the clip is a path and the gradients are `CGShading`s — which is
what Pen's PDF does (finding 9). Icons (`PenIconFontRenderer.swift:60`) take the same route with the icon node's box
as domain (measured 40→160 on a 120-pt icon at x 40).

**Strokes.** Turn the stroke into a region, then fill it like a shape:

- Uniform width: `path.copy(strokingWithWidth: w′, lineCap:, lineJoin:, miterLimit:)` — or `addPath` +
  `replacePathWithStrokedPath()` + `clip()` on the context — with `w′ = w` for center and `2w` for inner/outer, then
  intersect with the shape (inner) or its even-odd complement (outer), exactly the clips the solid path uses today
  (`PenStrokeRenderer.swift:53-75`). Then `renderFills(stroke, clip: region, domain: node rect)`.
- Per-side widths: build the ring as a path — outer rectangle minus inner rectangle, each side offset by its width
  times 0 (outer edge for inner), ½, or 1 according to `strokeAlignment` (default center) — clipped to the rounded
  shape for corner radii, then the same fill call. This is also the fix for finding 5 with a solid color.
- Lines (`renderLine`) use the uniform path.

Pitfalls: miter joins in `copy(strokingWithWidth:)` must use the same miter limit the solid path uses (CG default 10)
or corners will differ from today's MAE fixtures; an open path's outline is fine to fill with `.winding`; the solid
single-color case should keep `strokePath()` so `render-strokes-and-paths` does not move.

**Mesh and shader** on text and strokes need nothing new here: once `PenFillRenderer` can draw them for shapes (see
`2026-09-26-mesh-gradients.md`), the clip/domain split gives them text and strokes too.

## What the React emitter should emit

- **Text:** what Pen emits, minus its bugs — `backgroundImage` with the paint (every enabled fill as one comma-separated
  layer, top fill first, a solid as `linear-gradient(c, c)`), `backgroundSize: "100% 100%"`, `backgroundRepeat:
  "no-repeat"`, `backgroundClip: "text"`, `WebkitBackgroundClip: "text"`, `WebkitTextFillColor: "transparent"`,
  `color: "transparent"`; fill blend modes as `backgroundBlendMode` (Pen drops them). The element's box is the node box
  already, because the emitter sizes fixed text and the auto box follows content. Use the emitter's own
  rotation→angle conversion, not Pen's auto-text `0deg`. Image fills map `fill/fit/stretch` to
  `cover/contain/100% 100%` as `emitSingleComplexFill` already does.
- **Uniform strokes on rectangles and frames:** `box-shadow`/`outline` cannot carry a gradient. The robust CSS is a
  positioned pseudo-element (or wrapper child) inset by the alignment offset, with the paint as its background sized to
  the *node* box (`backgroundOrigin`/`backgroundSize`/`backgroundPosition` so the domain matches Pen) and the border
  region cut out with `mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0); mask-composite:
  exclude` and `padding: <width>`. It keeps `border-radius` (which `border-image` ignores) and handles per-side widths
  as per-side padding. Pen's SVG overlay is the alternative when a node is already an SVG.
- **Paths and ellipses (already SVG):** `stroke="url(#id)"` with a `<linearGradient gradientUnits="userSpaceOnUse">`
  spanning the node box; inner/outer alignment as a `clipPath`/`mask` of the shape with `strokeWidth` doubled —
  the same construction as Pen's export.
- **Image, mesh and shader strokes:** Pen's own export drops them; the mask technique above handles images. Mesh and
  shader need a rasterized background, which is how Pen does mesh/shader *fills* (`data:image/webp`) — open question 4.

## Summary table

"Domain" is where the paint's 0…1 space sits. Every Pen cell is from the renders above; "stripped" means Pen deletes
the key on load and draws nothing.

| Fill type | Text: Pen renders? | Text: domain | Text: Woodcase today | Stroke: Pen renders? | Stroke: domain | Stroke: Woodcase today |
|---|---|---|---|---|---|---|
| Solid color | yes | — | last solid only; stack/blend ignored | yes | — | first solid only; stack/blend ignored; per-side always inner |
| Linear gradient | yes | node box (auto width: box minus 1–7 pt) | black (no solid) or the solid | yes, all alignments | node box, padded outside | not drawn |
| Radial gradient | yes | node box | as above | yes | node box, padded | not drawn |
| Angular gradient | yes | node box | as above | yes | node box, padded | not drawn |
| Image (stretch/fill/fit) | yes | node box, mode applied to it | as above | yes | node box; decal (outer stroke may vanish) | not drawn |
| Mesh gradient | yes | node box | as above | yes | node box | not drawn |
| Shader | yes | node box, `@resolution` = node size | as above | yes | node box | not drawn |
| Stacked fills, opacity, blend | yes, per-fill through glyph coverage | node box | collapses to one solid | yes | node box | collapses to first solid |
| Any paint as a **text stroke** | stripped | — | never drawn (matches) | n/a | | |
| underline / strikethrough | stripped | — | drawn (diverges) | n/a | | |

## Proposed leaves

In order; each is one agent's file surface. Criteria are written so a test can check them.

1. **Per-side stroke alignment (bug, solid colors).** `PenStrokeRenderer.swift` only. Criteria: a regression test
   with `perside/perside.pen`'s three boards, asserting band extents within 0.5 pt of Pen's (finding 5 table) at 2x;
   the wrong doc comment at `:80-84` corrected; `render-strokes-and-paths` MAE unchanged ±0.05.
2. **Split clip from domain in `PenFillRenderer`.** `PenFillRenderer.swift`, `PenRenderer.swift` (call sites and the
   even-odd path). Criteria: every existing MAE fixture unchanged ±0.05; unit tests that a gradient drawn into a
   clip smaller than its domain keeps the domain's ramp (the pixel at a known x reads the expected `t`); an even-odd
   donut with a gradient fill draws the gradient. Consider fixing the rotated-linear and angular mapping gaps
   (rect halves 11.5 and 12.4) here or in a sibling leaf first — ask Ben (open question 5).
3. **Non-solid paints on text — linear gradient first.** `PenTextRenderer.swift` (+ a `PenTextRenderer+GlyphPath.swift`
   extension), `PenIconFontRenderer.swift`. Criteria: committed `render-text-fills.pen` with Pen 2x references;
   an analytic test (the `analyze.py` fit, in Swift) finds stop 0/stop 1 within 0.5 pt of the node box on the
   fixed-width, fixed-height, multi-line and ragged boards, and within the box on auto width; twins' text half MAE ≤
   the same text in solid white + 1; solid single-fill text output byte-identical to today; `woodcase render --format
   pdf` of a gradient text contains a shading, not a bitmap; the icon star fits 40→160. Radial, angular, image, stacks,
   opacity and blend come with it for free and get one assertion each.
4. **Non-solid paints on strokes.** `PenStrokeRenderer.swift`. Criteria: committed `render-stroke-fills.pen` with Pen
   2x references; fitted domain on rect inner/center/outer, ellipse, path and per-side boards within 0.5 pt of the node
   box; UV outer `stretch`/`fit` draw nothing and `fill` draws only the two side bands; stack and multiply twins match
   Pen within MAE 1; solid strokes unchanged ±0.05 on existing fixtures.
5. **React: paints on text.** `ReactEmitter+Text.swift`, `ReactEmitter+Styles.swift`; goldens regenerated and read.
   Criteria: a gradient-text component golden with the declarations above; stacked fills as layers with
   `backgroundBlendMode`; the WebView regression harness renders `twin-lin-h`'s text with the domain fit within 1 pt of
   the box (a WebView page shot through the existing `WebViewRegressionTests` machinery).
6. **React: paints on strokes.** `ReactEmitter+Styles.swift`, `ReactEmitter+Shapes.swift`. Criteria: goldens for a
   gradient stroke on a rounded rect (mask technique), on a path (SVG paint server), and per-side; WebView domain fit
   within 1 pt on the rect board.
7. **Lint and schema help for what Pen strips** — only if Ben confirms finding 4 against Pen.app. `Lint/`,
   `PenNode+TextData` schema metadata. Criteria: `woodcase lint` warns on `stroke*`, `underline` and `strikethrough`
   on a text node with a message naming Pen's behavior; `woodcase help schema text` says the same.

RapidPro renders from Woodcase's model and will want leaves 3 and 4's semantics mirrored; I did not look at it.

## Open questions for Ben

> **Decisions (integrator, 2026-09-26, under Ben's standing permission for two-way calls; reported to Ben).** (1) Accept "node box" as the text paint domain with a tolerance; the auto-width offset tracks Woodcase's own text-measurement gap and is not chased here. (2) Confirm the stripping in Pen.app (Ben allows driving it); if confirmed, Woodcase keeps drawing underline and strikethrough and `lint` warns that Pen will not show them or a text stroke. (3) React output matches Pen's renders, not its HTML export. (4) Mesh and shader fills in React use a pre-rendered raster, consistent with Ben's mesh ruling. (5) The rotated-linear and angular gradient gaps are a separate leaf that lands before text paints. (6) Two fixture files: one for text, one for strokes.

1. **Auto-width text domain.** Pen's horizontal paint domain on auto-width text is 1–7 pt narrower than the node width
   it reports, anchored left. Chase it (more probes: size, weight, letter spacing, trailing space) before leaf 3, or
   accept "node box" and a tolerance?
2. **Underline, strikethrough and text strokes.** The 0.3.9 engine strips all three from text on load and draws
   none. Woodcase draws underline and strikethrough and emits them to React. May I confirm in Pen.app 1.2.14 (one
   probe file opened and exported)? If confirmed: stop drawing them, lint them, or keep them as a Woodcase extension?
3. **React fidelity target.** Match Pen's export (including `border-image` per-side strokes and dropping image strokes)
   or match Pen's *renders* (mask technique, blend modes kept)? I recommend the renders.
4. **Mesh and shader in React.** Pen rasterizes them into `data:image/webp`. Is a rasterized background acceptable
   for Woodcase's React output once the CG renderer can draw them, or should they stay unsupported there?
5. **Existing shape-gradient gaps.** Rotated linear gradients with a center/size, and angular gradients, already differ
   from Pen on plain rectangles (MAE 11.5 and 12.4). Fix those first (text and strokes inherit them), or file them
   separately?
6. **Fixture size.** One 50-board file, or split per surface (text / strokes) as proposed? Either way a few hundred KB of
   PNGs at 2x.

## Appendix: reproduce

All from `local/NXgRKl-fills/`, sandbox off for `pen`, `pen-oracle` and `woodcase`.

```
python3 make_fixture.py                                   # .pen, uv.png, uv.frag
../../scripts/pen-oracle text-and-stroke-fills.pen --out pen --scale 1,2
for n in $(python3 -c "import json;[print(b['name']) for b in json.load(open('text-and-stroke-fills.pen'))['children']]"); do
  for s in 1 2; do ../../.build/debug/woodcase shot text-and-stroke-fills.pen "$n" --scale $s --out "wc/text-and-stroke-fills-$n@${s}x.png"; done
done
python3 analyze.py pen text-and-stroke-fills 2            # domains (finding 3)
python3 analyze_clamped.py pen text-and-stroke-fills 2    # stroke domains without padded samples
python3 mae.py pen wc text-and-stroke-fills               # MAE table
python3 projected.py                                      # projected text MAE (needs coverage.pen renders in wc-cov/, pen-cov/)
# finding 4: keys Pen strips from text
printf 'save()\nexit()\n' | pen interactive --in probe-text-props.pen --out probe-text-props-saved.pen
# finding 8: HTML export (ids from html/ids.json)
printf '%s\n' "execute({input: \"Export([...ids...],'html-css','$PWD/html/export-css.html',{includeLayerIds:true})\"})" 'exit()' \
  | pen interactive --in text-and-stroke-fills.pen --out html/session.pen
```
