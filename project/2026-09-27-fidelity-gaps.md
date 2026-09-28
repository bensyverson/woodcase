# 2026-09-27 — Fidelity gaps: where Woodcase draws differently from Pen

Research and plan for the "fidelity gaps" feature (agent `gaps`, worktree `wt/gaps` at `721cd59`). It inventories
every place found where the Core Graphics renderer, the layout engine, the React emitter or the SwiftUI emitter
draws something other than what Pen draws. Each gap has evidence, a classification and a proposed fix. The plan
at the end groups the fixes by the files they touch, in `job import` format.

Every gap is classified as Ben asked on 2026-09-27:

- **(a) Woodcase is wrong.** Fix it.
- **(b) Pen is arguably buggy and likely to catch up.** Keep Woodcase's behaviour, document the difference and
  accept the MAE gap. These are listed under *Kept on purpose*, not in the plan.
- **(c) A genuine design divergence.** A decision for Ben (see *Decisions for Ben*).

## How the figures were taken

- **Pen references.** Every Pen figure comes from `scripts/pen-oracle <file> --scale 2`, headless Pen, run with
  the sandbox off. The installed pen CLI and Pen.app are 1.2.14 (Pen.app's `CFBundleShortVersionString`). Pen's
  re-save is never used as evidence of what Pen draws (see gotchas); only its PNG exports and its layout JSON are.
- **Woodcase CG figures** come from two sources:
  - the snapshot suites: `swift test -j 3 --skip-build --filter "PenSnapshotTests|PenBankingAppTests|PenIconFontSnapshotTests|PenTextPaintTests|PenTextLineHeightTests|PenWoodcaseAppTests|PenShadowSnapshotTests|PenBlurSnapshotTests|PenGradientGeometrySnapshotTests|PenStrokeFillTests|PenFillDomainTests|PenArcDonutTests|PenGroupShadowSnapshotTests|PenMesh.*Snapshot|PenUnfilledTextPaintTests|PenViewBoxSnapshotTests|KitLibraryFixtureTests|SlotOverrideKeysSnapshotTests|PenPerSideStrokeAlignmentTests"`
    (88 tests in 21 suites, all green);
  - for probes and boards the suites do not print: `woodcase shot <file> <board> --scale 2 --out <png>`, scored
    with `scripts/png-mae <render> <reference>`. That script is new. It uses the suites' MAE definition
    (premultiplied sRGB bytes, alpha included), so its figures rank boards but are not gates. `shot` draws with
    the fonts in `~/.woodcase/fonts`, not the test suite's committed fonts.
- **SwiftUI and React figures** come from `performance/mae-baseline.csv` at `721cd59`, the figures the last
  committed full run recorded. `SwiftUIRenderTests` was **not** re-run: its batch compile takes 574 s or more
  under load, and another agent owns that support code (`T5l1ul`).
- **The machine was loaded throughout.** Four other agents were building. The 1-minute load average read 87–116
  during this worktree's cold build and 37–63 while the suites and probes ran (`uptime`). MAE is deterministic,
  so load changes only the timings.

The probe documents are committed as fixtures (below), so every Pen figure here can be re-run. All scratch work
is in the session scratchpad under the `gaps-` prefix.

### New fixtures (clean Pen-oracle references, self-authored)

Each fixture was generated in place with `scripts/pen-oracle Tests/WoodcaseTests/Fixtures/<name>.pen --scale 2`,
which writes its PNGs, `.layout.json` and `.pen-saved.pen` beside it. Two further checks passed:
`scripts/pen-provenance-check` reports 0 unexplained overlaps, and `EditableDocumentExpansionParityTests`, which
parses every fixture, is green. No test reads these fixtures yet; each leaf below wires in the one it needs.

| Fixture | Boards | Side files |
|---|---|---|
| `render-font-faces.pen` | `plexmono-{400,700,italic,700-italic}`, `spectral-{400,700,italic}`, `inter-italic`, `lora-italic`, `instrumentserif-italic` | — |
| `render-rotated-free.pen` | `rrect`, `rtxtf`, `rtxta`, `rtxts` (a rectangle, fixed-width text, auto text and an unrotated control, each at `x: 80, y: 60, rotation: -20` in a `layout: none` frame) | — |
| `render-per-side-shapes.pen` | `{ellip,polyg,pathx}-top12` (widths t12 r2 b6 l0) and `-top2` (t2 r10 b4 l6) | — |
| `render-shader-fills.pen` | `uv-rect`, `uv-text` (text + icon), `checker-default`, `checker-uniforms`, `sdf-rounded`, `backdrop`, `time`, `image`, `half-opacity` | `shader-{uv,checker,sdf,backdrop,time,image}.frag`, `shader-quad.png` |
| `render-script-node.pen` | `script` (a script node with `inputs`) | `script-bars.js` |

## Findings

### F1. Shader fills: Pen runs them, Woodcase draws nothing on every target (a, and needs Ben for the approach)

**What the format carries.** The 2.17 schema defines a shader fill as `{type: "shader", url, uniforms?,
enabled?, blendMode?, opacity?}`: a WebGL 1.0 (`#version 100`) fragment shader file relative to the .pen file.
Pen's own agent skill, `Pen.app/Contents/Resources/app.asar.unpacked/out/skills/pen-dev/scripts-and-shaders.md`,
documents the full contract:

- Uniform types: `float`, `int`, `vec2/3/4`, `ivec2/3/4` (as numbers, arrays or `#RRGGBB`), and `sampler2D` (an
  image URL).
- Annotations in block comments: `@color`, `@default`, `@resolution` (the output size), `@mouse`, `@time`
  (seconds), `@sdf` (a `sampler2D` holding the node shape's signed distance in `r` and its gradient in `gb`),
  `@backdrop` (a `sampler2D` holding what is rendered behind the node), and the UI-only `@min`, `@max`, `@range`
  and `@label`.
- `textureSize(sampler, lod)` is available on top of GLSL ES 1.00.

**What Pen draws.** Every feature probed runs in the headless exporter (`render-shader-fills.pen`):

- uniform defaults and `uniforms` overrides;
- `@resolution`, with `gl_FragCoord` in node points, not export pixels: a 20-unit checker cell is 40 px at 2x;
- a `sampler2D` image, filtered linearly;
- `@sdf` (distance bands on a rounded rectangle);
- `@backdrop` (red and green behind the node drawn inverted);
- `@time`, which is **0** in an export;
- fill `opacity`;
- the node's box as the domain on text and icons. PRFPX5 had already seen a solid-red shader colour Pen's glyphs.

**What Woodcase does.** CG draws nothing (`PenFillRenderer.swift:91`, "Shader fills are not executed").
SwiftUI writes nothing and warns (`SwiftUINodeEmitter+Paint.swift:54`). React writes nothing and does not warn
(`ReactEmitter+PaintLayer.swift:72`). `woodcase render` and `shot` say nothing.

> **Updated 2026-09-27 (leaf `dYIzYU`, phase 1):** Woodcase still draws nothing, but no longer silently.
> `woodcase lint` reports each enabled shader (`shader-not-drawn`, warning), `render` and `shot` print one
> warning per document naming the shader nodes (`ShaderFills.diagnostic(under:)`), and React warns per node
> with SwiftUI's wording, `React does not emit shader fills yet`. Measured with `shot` + `png-mae`
against Pen's exports:

| Board | `uv-rect` | `uv-text` | `checker-default` | `checker-uniforms` | `sdf-rounded` | `backdrop` | `time` | `image` | `half-opacity` |
|---|---|---|---|---|---|---|---|---|---|
| CG MAE | 63.75 | 11.72 | 127.50 | 95.63 | 76.67 | 68.75 | 159.25 | 95.63 | 63.63 |

**The options, weighed honestly.**

| Option | Target | Lift | Fidelity | Risk |
|---|---|---|---|---|
| Warn and document | all | S | none, but honest | none |
| A GLSL ES 1.00 front end (lexer, parser, type checker) plus a CPU evaluator compiled to Swift closures, with bilinear `texture2D`, an SDF raster of the node's outline and the backdrop capture the background blur already does (`PenEffectRenderer`) | CG, and so `render`, `shot`, `serve`, PDF (as an image) and RapidPro's reference | L (~5k lines, 4–5 leaves) | exact up to float precision, `@time = 0` | per-pixel interpretation: roughly 0.2–2 s for a 400×200 fill at 2x, which wants measuring; the language surface is small (no recursion, constant-bound loops) but the builtin library is about 60 functions |
| Metal: translate GLSL→MSL and run on the GPU | CG | L, plus the same front end or a C++ dependency (glslang + SPIRV-Cross) | exact | **fails headless**: no `MTLDevice` inside the Bash sandbox or on a GPU-less host (the Core Image gotcha), and no Linux; rejected for the renderer |
| WebGL in a `WKWebView` | CG | M | exact | macOS only, async, and WebKit's WebGL also needs the GPU; rejected |
| Emit the shader live: a small `PenShaderCanvas` support component that compiles the `.frag` verbatim in WebGL 1 with the uniforms, `@resolution`, `@time` (animating) and `@mouse` | React | M | exact (Pen is Chromium running the same GLSL) | `@backdrop` cannot read the page behind an element (warn); `@sdf` needs the SDF computed in JS or baked at generate time; on text it needs the canvas behind `background-clip: text` |
| Bake a raster at generate time from the CG evaluator | React / SwiftUI | S once CG runs shaders | static, `@time = 0` | loses animation; for React it follows the 2026-09-26 decision (4), "mesh and shader in React as raster" |
| Translate GLSL→MSL at generate time, compile with `xcrun metal` into a `.metallib` resource, draw with `.colorEffect` / `.layerEffect` (`Shader.Argument.image` for samplers and a baked SDF) | SwiftUI | L (shares the front end) | exact on device | `@backdrop` cannot sample behind a view (warn); generation then needs the Metal Toolchain (installed here: `xcrun metal`, metalfe-32023.921.6); whether plain `swift build` compiles a package's `.metal` resources is unverified |

**Recommendation.**

1. Now: warn everywhere (plan leaf *Shader fills warn wherever they are not drawn*).
2. Then the CG evaluator, because every other target can reuse it as a raster, and it keeps `render` headless
   and cross-platform.
3. React goes live in WebGL: Pen itself runs in Chromium, so emitting the shader is cheaper and more faithful
   than a raster. This revisits decision (4) of 2026-09-26 for shaders only.
4. SwiftUI takes the baked raster until MSL translation has earned its lift.

The deciding fact is missing: how often do Ben's real files use shaders? That makes this a decision for Ben
(D1).

### F2. Script nodes: Pen runs the JavaScript, Woodcase draws nothing (a, needs Ben for where it runs)

**What Pen does.** Pen runs a `script` node's `scriptUri` headless. The contract in the same skill file:
`/** @schema 2.11 */`, `@input` declarations, a `pencil` object (`width`, `height`, `input`), a returned array
of .pen nodes, and a `Math.random` that is deterministic. `render-script-node.pen` draws four red bars and a
text reading `0.467327`. Two separate oracle runs gave byte-identical PNGs, so the PRNG is seeded and stable.
Pen's layout JSON and its re-save do **not** include the generated children: they exist only at draw time.

**What Woodcase does.** It treats a script node as a sized empty leaf (PenRendering.md, *Script Nodes*). CG
draws nothing, React writes an empty `<div>` (`ReactEmitter+Script.swift`) and SwiftUI writes a placeholder.
CG MAE 30.64 against Pen's export (`shot` + `png-mae`).

**The fix.** Expand script nodes into children before layout, as the ref expander does. Woodcase already has a
JavaScriptCore host (`WoodcaseScripting`), but it is Apple-only, while the core library is cross-platform. Two
things need Ben:

- where the expansion lives: probably a `WoodcaseScripting` stage that the CLI and the viewer call, drawing
  nothing on Linux as today;
- whether to reproduce Pen's `Math.random` sequence. Its seed and algorithm are unknown. A probe that returns
  the first N values under different node ids and inputs would identify it, if it is a standard generator.

The emitters would inline the generated nodes statically. Lift M (expansion) + S–M (PRNG). Decision D2.

### F3. Bold and italic faces of Google families are drawn in the regular face (a)

This is worse than the brief said: Woodcase does not even synthesize the face.

> **Fixed 2026-09-27 (leaf DAmmQF).** The resolver now resolves faces, not families: every cached file is
> registered, each face drawn fetches the file its METADATA names, and the METADATA is cached beside the files.
> `GoogleFontFacesSnapshotTests` renders every board below through a cold cache and scores 2.20–2.70
> (`swift test -j 3 --filter GoogleFontFacesSnapshotTests`); see `PenGoogleFonts.md`, *Faces*.

- On a cold cache, `downloadRegularFace` (`GoogleFontResolver.swift:282`) fetches one METADATA entry, weight 400
  normal.
- On a warm cache, `resolveCached` (`GoogleFontResolver+Registration.swift:92`) registers the **first `.ttf` in
  directory order** and returns, whatever else the cache holds.
- So a static family draws every weight and style in whichever single file wins. A variable family's separate
  italic file (`Inter-Italic[opsz,wght].ttf`, `Lora-Italic[wght].ttf`) is never fetched, so its italics are
  upright.
- The worst case is `~/.woodcase/fonts/instrumentserif/`, which holds `InstrumentSerif-Italic.ttf` and
  `-Regular.ttf`. **Upright Instrument Serif renders italic**: its MAE against Pen's *italic* export is 2.678,
  identical to the italic board's.
- `dmmono/` holds Light, Medium and Regular, so one arbitrary weight draws everything.

Measured with `shot` + `png-mae` against `render-font-faces.pen`. The control rows are the regular faces:

| Board | MAE | What Woodcase drew |
|---|---|---|
| `plexmono-400` | 2.46 | correct (control) |
| `plexmono-700` | 7.32 | regular, upright |
| `plexmono-italic` | 8.54 | regular, upright |
| `plexmono-700-italic` | 11.02 | regular, upright |
| `spectral-400` | 2.25 | correct (control) |
| `spectral-700` | 15.76 | regular |
| `spectral-italic` | 14.07 | regular |
| `inter-italic` | 13.82 | upright (variable family, italic file never fetched) |
| `lora-italic` | 14.81 | upright |
| `instrumentserif-italic` | 2.68 | italic, by luck of directory order |

**Consequences.**

- Layout drifts too: bold is wider, so `fit_content` boxes and wraps move.
- Generated SwiftUI packages bundle "every file the cache holds" (`GoogleFontResolver+Bundling.swift:117`), so
  they inherit the same missing faces.
- React is unaffected: it imports Fontsource packages.

**The fix.**

- Resolve the faces a document uses: its (weight, style) pairs, which font collection already walks. For a
  static family, fetch each face's file; for a variable family, fetch the upright file and, when italic is used,
  the italic file.
- Cache each file and register them **all**, from file URLs.
- Replace the directory-order short-circuit with a per-face check.
- Bundle the same set for SwiftUI.

Lift S–M, two-way. Test against a fetcher serving local files, not the network. Mind the gotcha that only one
test per run may watch a family go from absent to present: use families no other suite registers (IBM Plex
Mono, Spectral and Lora are OFL; commit them or renamed copies, as `rename-font-family` does).

### F4. A rotated node placed by `x`/`y` sits in the wrong place in CG and SwiftUI (a)

> **Closed 2026-09-27 (leaf `nAuBKh`).** The fix below was right and incomplete: Pen *flips* a free node about
> its anchor too (a `flipX` rectangle settles its whole width left of its `x`), and roots, absolute children of
> flex frames and turned frames nested in `layout: none` follow the same rule — all measured with
> `scripts/pen-oracle` on the new `render-transformed-free.pen`. The CG renderer also drew any turned node not
> fixed on both axes (auto text, fixed-width text) into its turned bounds rather than at its own size; it now
> recovers the unturned size (`PenLayoutEngine.unturnedSize(of:bounds:)`). CG MAE: `rrect` 0.007, `rtxtf` and
> `rtxta` 0.144, `txt-rotated` 0.017 (`swift test --filter PenTransformedFreeTests|PenTextPaintTests`).

Pen turns a node positioned by `x`/`y` (in a `layout: none` parent, or absolute) about its **top-left anchor**.
Its settled layout for `render-rotated-free.pen`'s rectangle (200×60 at `x: 80, y: 60`, `rotation: -20`) is
`x: 59.479, y: 60, 208.46 × 124.79`: the rotated bounding box, which reaches 20.5 pt left of the anchor. That
20.5 pt is 60 × sin 20°.

Woodcase's layout (`woodcase tree`) reports `80,60 208.46×124.79`: the same size, with the box's corner pinned
at the anchor, and CG then pivots at that box's centre. Everything drawn lands shifted.

| Board | CG MAE (`shot` + `png-mae`) |
|---|---|
| `rrect` (rectangle) | 2.57 |
| `rtxtf` (fixed-width text) | 4.98 |
| `rtxta` (auto text) | 4.98 |
| `rtxts` (unrotated control) | 0.14 |
| existing `render-text-fills-txt-rotated` (a rotated gradient text), CG | 7.33 |
| the same board, SwiftUI (`mae-baseline.csv`) | 7.33 |

`txt-rotated` is the worst CG board in the repo, and SwiftUI scores the same because it copies CG's rule.

React already matched Pen here since `mkPpjZ` (`transformOrigin: "0 0"`, `TransformPivot`). This is the same
finding applied to the other two targets. PenEngine.md states the wrong rule: "For a sized node the layout rect
is the rotated bounding box anchored at the declared `x`/`y`". That is a documented wrong cause, to be corrected
in place.

**The fix.** For a node its parent does not lay out, offset the rotated bounding box's origin by where the
anchor rotation puts it: the minimum of the four rotated corners, relative to the anchor. The CG centre pivot
inside that box then reproduces Pen's pixels, and SwiftUI's `.offset` follows. Flex children are unchanged: Pen
grows the slot to the turned bounds, and that already matches.

Lift M. Risk: every layout golden with a rotated free node moves, and `fit_content` unions that include one
move. `render-transforms-and-effects` (CG 0.886) may improve.

### F5. Icon glyphs sit 1–3 pt off Pen's position (a)

> **Resolved 2026-09-27 (leaf `VMKixs`):** Pen places the glyph by the font's metrics: the
> advance is centred across the box, and the line box is centred down it. The line box is
> ascent plus descent, each rounded to a whole point at 14 pt. `render-icon-placement.pen` and
> `scripts/icon-placement-fit.swift` are the evidence, and PenIconFonts.md ("Where the glyph
> sits") states the rule. CG `icon-font-test` went from 5.25 to 1.24 (gate 1.86), `icon-grad`
> from 1.66 to 0.042, and SwiftUI `parser-icon-font` from 4.73 to 0.84. The table below
> records the gap as it was measured.

`parser-icon-font.pen` against `icon-font-test.png` scores CG **5.25** (`PenIconFontSnapshotTests`, gate 7.87),
the highest MAE among the gated CG boards. Ink bounding boxes in export pixels at 2x, Pen → CG:

| Icon | Pen | CG | Difference |
|---|---|---|---|
| Material Symbols, 48 pt | y 44–115 | y 47–119 | 1.5 pt low, slightly larger |
| Phosphor `chat-dots-thin` | y 45–90 | y 40–86 | 2.5 pt high |
| Lucide `ellipsis` | y 56–103 | y 57–104 | 0.5 pt low |
| Feather `bell` | y 34–77 | y 34–78 | about the same |

`PenIconFontRenderer` and SwiftUI's `PenIconShape` centre the glyph's **ink** in the box. Pen evidently places
the glyph by the font's metrics, since the offsets differ by library. `icon-grad` (1.66, the highest
text-paint ceiling) is probably the same cause.

**The fix.** Probe one glyph per library at two sizes and in a non-square box with `pen-oracle`, fit Pen's
placement rule (em box, or ascent/descent centring), then apply it in both `PenIconFontRenderer.swift` and the
SwiftUI icon support template. Lift M.

### F6. A per-side stroke width on an ellipse, polygon or path (a)

PenRendering.md calls this "not what Pen draws" and PenCodeGen.md "not established". It is established now.
Pen draws a **uniform centred stroke of the `top` width** and ignores the other three sides. Evidence from
`render-per-side-shapes.pen`, both width sets:

- With `t12 r2 b6 l0`, the ellipse ring reaches 6 pt past the 30–170 × 30–130 box on every side.
- With `t2 r10 b4 l6`, it reaches 1 pt.

Woodcase draws inner bands along the box, clipped to the shape: MAE 15.56 (ellipse), 15.30 (polygon) and 14.46
(path), `shot` + `png-mae` on the `-top12` boards.

Following Pen is the only defensible target, since the format gives no other meaning. `woodcase lint` should
also say that only `top` counts.

> **Corrected 2026-09-27 (leaf `bLU8nV`):** "centred" held only because the fixture's shapes set no
> `strokeAlignment`, whose default is centre. Pen draws **a uniform stroke of the `top` width under the node's
> own alignment, join and cap**: probed with `scripts/pen-oracle` on inner and outer boards (now in
> `render-per-side-shapes.pen`, 14 boards), the 12 pt ring lies wholly inside or outside the outline, pixel for
> pixel the same as a uniform `strokeWidth: 12` (`scripts/png-mae` 0.000). With no `top` Pen draws no stroke,
> and a line takes the rule too. CG now draws all 14 boards at MAE 0.00–0.17 (`PenPerSideShapesTests`).

- CG: `PenStrokeRenderer+PerSide.swift`.
- SwiftUI: `penSideBands` in `SwiftUINodeEmitter+Stroke.swift` and the stroke support template.
- React: its SVG stroke path.

Lift S. Classified (a), with a note: Pen's choice of `top` looks arbitrary and could change, so pin it with the
fixture and say so in the docs.

### F7. React writes no effects on text, icons, paths, polygons, lines, arcs or groups (a)

`ReactEmitter.emitEffects` is reached only from frames, rectangles, CSS ellipses and browsers
(`ReactEmitter+Frame.swift:154`, `+Shapes.swift:35,190`). `woodcase generate react` on a probe that gives a text,
a lucide icon, a path and a group each an outer shadow and a layer blur emits **none** of them: no `boxShadow`,
no `filter`.

Where effects are written, `ReactEmitter+Styles.swift:279-331` has smaller gaps:

- **Shadow order is reversed.** CSS paints the first `box-shadow` on top; Pen draws the array bottom first.
- **A shadow's `blendMode` is dropped.**
- **Layer blur is truncated to whole pixels.** It emits `Int(radius / 2)`, so a radius of 5 becomes 2 px, not
  2.5.
- **Two blur effects produce two `filter` keys.** Only one survives.
- **A background blur is emitted on a node with no visible fill.** Pen draws none there, and CG follows Pen via
  `hasVisiblePaint`.

**The fix.**

- Text: `text-shadow`, cast by the glyphs as Pen casts them.
- Icons and SVG shapes: `filter: drop-shadow(…)`.
- Groups: a drop-shadow over the group's content (an approximation of Pen's opaque silhouette: a translucent
  child casts a weaker shadow). Inner shadows off the box want an SVG filter.
- Mirror CG's rules, as `PenRendering.md` *Effects* lists them.

Lift M. No React board measures effects today (see F8), so this should land after the harness.

### F8. React has no MAE sweep over the renderer's fixtures (verification gap)

`ReactPaintWebViewTests` measures 17 stroke and paint boards (0.00–0.16) and 3 text boards with no MAE limit.
`ReactTransformStateWebViewTests` measures 9 transform boards (≤ 0.04). `WebViewRegressionTests` measures the
component and screen fixtures (`StatCard` 3.95, `lab` 3.59, `settings` 2.74). Nothing renders React against
`render-shadows`, `render-background-blur`, `render-group-shadows`, `render-gradients`, `render-gradient-geometry`,
`render-mesh-gradients`, `render-text-line-height`, `text-natural-line-height`, the `layout-*` boards, or the new
fixtures above. That is why F7 and F9 went unseen.

**The fix.** A `ReactRenderWebViewTests` suite, the React counterpart of `SwiftUIRenderTests`: emit each board,
render it in WebKit through the existing `WebViewTestHarness`, record its MAE against Pen's PNG with the reason,
and gate at CG + 1.0 wherever React can match. Lift M. It is test code only, but serialized and load-sensitive
(see the WebKit gotchas).

### F9. React sets a text with no `lineHeight` at 1.3 (a)

`ReactEmitter+Text.swift:45-48` writes `lineHeight: 1.3` "to approximate Core Text". Pen's natural pitch is the
font's ascent + descent + leading, rounded to a whole point: Inter at 16 pt is 19 pt, a factor of 1.19
(PenCodeGen.md, *Text*). CG and SwiftUI use it (`PenTextMeasurer.naturalLineHeight(of:)`). So every React
paragraph without a line height is about 9 % taller than Pen's, and auto-height boxes grow.

**The fix.** Emit the pitch in px, computed at generate time from the font Woodcase resolves, or CSS
`line-height: normal` where the font is not known. Lift S.

It shares `ReactEmitter+Text.swift` with the open `Wo6Vni`, which "names" has claimed, so it goes after that.

### F10. SwiftUI: what it cannot draw, and a one-pixel `fit_content`

From `SwiftUINodeEmitter+*.swift`'s `unemitted` warnings and the baselines in `SwiftUIRenderTests`,
`SwiftUIStateRenderTests` and `SwiftUIScreenRenderTests`:

| Gap | Today | Class | Fix, lift |
|---|---|---|---|
| Background blur is a `.ultraThinMaterial` | `render-background-blur-flip` 29.32, `-r8` 25.62, `blur1` 7.95, `blur2` 8.35, `blur3` 10.38 (baselines, "by design") | (c), ruled | kept (see below) |
| Background blur on text and groups | not drawn, warning | (c) | follows the Material ruling |
| Inner shadow on text | not drawn, warning | (a) | a text-masked inner shadow in `PenSupport+Effects.swift`; S–M |
| `textAlign: justify` | drawn leading, warning (SwiftUI `Text` has no justification) | (c) | accept with the warning; a TextKit-backed view would cost the idiom |
| Remote (`http`) image fills | `AsyncImage(url:)`, fetched at draw time (fixed) | (c), ruled | `AsyncImage`, not a generate-time download (D4, leaf `46XAVC`); done |
| Themed number variables in effects, rotation, gradient stop positions and per-side widths | dropped, warning | (a) | read the theme's numbers as colours already are; M, low priority |
| A `fit_content` text frame one pixel narrower at 2x | `MoreLink` 5.96, `Chip-selected` 4.68, `Chip` 3.13 (`SwiftUIStateRenderTests` baselines) | (a) | find the rounding: Pen's text width vs SwiftUI's; S investigation |
| `script` and `browser` nodes | placeholder, warning | F2 / ruled | — |
| Shader fills | nothing, warning | F1 | — |

> **Corrected 2026-09-27 (leaf `vVgtB2`):** the Core Graphics renderer did *not* draw an inner shadow on text, so the
> F10a row's "CG: draws it" below was wrong: `PenRenderer.renderOwnContent` drew a text's fill and never its inner
> shadows. It does now, from the glyphs in opaque ink, and SwiftUI draws them with `.penTextFill(innerShadows:)`;
> `render-text-shadows.pen` (six boards, `scripts/pen-oracle --scale 1,2`) pins both. F10b's cause was right but
> not the whole error: with the text box rounded up to whole points (`PenLineBox`), `MoreLink` measures 5.01,
> `Chip-selected` 4.15 and `Chip` 2.70 — sizes now equal to Pen's — and what remains is Core Text's glyph coverage,
> which the CG renderer shares (4.98, 4.09, 2.57).
>
> **Fixed 2026-09-27 (leaf `46XAVC`).** The row above recorded the pre-ruling recommendation ("download at
> generate time and bundle, as fonts are"); Ben's actual ruling, recorded under *Decisions for Ben* below, chose
> the opposite: SwiftUI draws a remote (`http`/`https`) image fill with `AsyncImage(url:)`, fetched by the running
> app at draw time, never downloaded while generating. `SwiftUIEmitterPaintTests` pins the emitted code;
> `PenCodeGen.md`'s Images section describes the rule. `project/2026-09-27-pen-missing-image-checkerboard.md`
> has the answer to "what does Pen draw for an image it cannot load" this leaf was asked to check: a checkerboard
> placeholder, not nothing — a gap kept on purpose, not built now.

### F11. Documentation that states a wrong cause (a, docs only)

- **PenInteroperability.md, *Stroked Path Positioning*.** It still says Pen "rasterize[s] the path and stroke
  together into a bitmap first" and that this is "the primary contributor to the higher MAE on stroke-heavy
  fixtures (~5.0)". Commit `89e43e8` proved the ~5.0 came from a stale 2026-03-23 reference: against today's
  export, CG measures 0.027. The section is a wrong documented cause and must say so, not be quietly reworded.
  Lift S.
- **PenEngine.md, rotated containers.** Wrong (F4); fixed with F4.

### F12. The test suites' IBM Plex Sans may not be the face Pen draws (investigate)

The suites register static `IBMPlexSans-{Regular,Medium,SemiBold}.ttf` (`Tests/WoodcaseTests/Fonts`). The CLI's
cache holds Google's variable `IBMPlexSans[wdth,wght].ttf`. With the variable face, `shot` + `png-mae` scores
0.55–1.96 on the eight `layout-text-*` boards (`list-row` 1.77, `chips` 0.75, `vertical-fill` 1.75). The gates
`SwiftUIRenderTests` recorded (CG + 1.0, in `mae-baseline.csv`) imply CG figures of 1.3–4.9 with the static
faces (`list-row` 4.9, `chips` 4.4, `vertical-fill` 4.3).

If Pen draws the variable face, the committed test fonts inflate those gates by up to 3. Confirm which face Pen
draws, for instance by comparing glyph widths in Pen's export, before tightening anything.

Two cautions:

- Commit `89e43e8` notes a real 3 pt layout gap on `layout-text-chips`' SemiBold labels.
- `PenTextMeasurer` belongs to another agent (`cHuvso`).

Lift S.

### Open issues in the tracker

`job ls BMjsh` lists six open issues. Only **`Wo6Vni`** is a fidelity item: React draws unfilled text and
icons black where Pen draws nothing. It is claimed by "names", so it is not re-planned here. F7 and F9 wait for
it because they share its files. The other five are performance or naming items: `Tdgxuz`, `MdCEmo`, `cHuvso`,
`K68yo3` and `T5l1ul`.

### The MAE table today

The worst gated or recorded boards per target, from the runs above:

| Target | Board | MAE | Held by |
|---|---|---|---|
| CG | `render-text-fills-txt-rotated` | 7.33 | only as SwiftUI's CG + 1.0 (F4) |
| CG | `icon-font-test` | 5.25 | 7.87 gate (F5) |
| CG | `pencil-wishlist` / `-dark` | 2.39 / 2.25 | 3.59 / 3.38 |
| CG | `pencil-home-collection` | 1.93 | 2.90 |
| CG | `icon-grad` | 1.66 | 1.9 ceiling (F5) |
| CG | `render-text-line-height` `tight-wrap` / `stacked` / `loose-wrap` | 1.57 / 1.27 / 1.05 | ceilings |
| CG | `render-transforms-and-effects` | 0.886 | 1.33 |
| CG | banking dark / light | 0.891 / 0.756 | 1.34 |
| CG | everything else printed (shadows, blurs, gradients, meshes, strokes, domains, slots) | ≤ 0.62 | margin-rule gates |
| SwiftUI | background blur boards | 7.95–29.32 | baselines, "background blur is a Material" |
| SwiftUI | `txt-rotated` | 7.33 | CG + 1.0 (F4) |
| SwiftUI | `MoreLink`, `Chip-selected`, `Chip` | 5.96, 4.68, 3.13 | baselines, "fit_content frame a pixel narrower" (F10) |
| SwiftUI | `layout-text-list-row` / `-chips` / `-vertical-fill` | 4.95 / 4.30 / 4.31 | CG + 1.0 (F12) |
| SwiftUI | `parser-icon-font` | 4.73 | CG + 1.0 (F5) |
| SwiftUI | woodcase-app screens | 1.23–2.46 | baselines, "text and shadow antialiasing" |
| React | `StatCard`, `lab`, `TextInput`, `settings` | 3.95, 3.59, 2.80, 2.74 | 5.5, 7.0, 5.0, 7.0 (loose, never tightened: see the margin-rule doc's *Out of scope*) |
| React | paint and transform boards | ≤ 0.16 | 1.0–2.0 / 0.3 |

The probe boards (F1–F6) are not gated anywhere yet. The leaves below add them.

## Inventory

L = lift (S/M/L). Class is (a), (b) or (c) as above.

| # | Gap | Pen | CG | React | SwiftUI | MAE (worst) | Class | Fix | L | Risk |
|---|---|---|---|---|---|---|---|---|---|---|
| F1 | Shader fills | runs GLSL ES 1.00 with uniforms, samplers, `@sdf`, `@backdrop`, `@time = 0` | nothing | nothing, no warning | nothing, warning | 159.25 (`time`), 11.72 on text | (a) + D1 | warn now; CPU evaluator for CG; React WebGL; SwiftUI raster | S / L / M / S | evaluator performance; scope |
| F2 | Script nodes | runs JS, deterministic `Math.random` | nothing | empty `<div>` | placeholder | 30.64 | (a) + D2 | expand before layout via JavaScriptCore | M–L | PRNG parity; Apple-only host |
| F3 | Bold/italic Google faces | the right face | regular (or an arbitrary cached file) | Fontsource, fine | bundles what the cache holds | 15.76 | (a) | fetch and register every used face | S–M | font-registration test isolation |
| F4 | Rotated free-positioned nodes | pivots at the `x`/`y` anchor | box pinned at anchor, centre pivot | correct since `mkPpjZ` | as CG | 7.33 | (a) | offset the rotated box origin in layout | M | layout goldens move |
| F5 | Icon glyph placement | by font metrics (to confirm) | ink-centred | icon packages | ink-centred | 5.25 | (a) | fit Pen's rule, apply in both | M | per-library differences |
| F6 | Per-side width on ellipse, polygon, path | uniform centred stroke of `top` | box bands clipped | SVG stroke | box bands | 15.56 | (a) | follow Pen, lint it | S | Pen may change it |
| F7 | React effects on text, icon, SVG shapes, groups; shadow order, blend, blur rounding, blur without fill | draws them | — | dropped | — | unmeasured | (a) | text-shadow, drop-shadow, mirror CG's rules | M | group silhouette approximated |
| F8 | React MAE sweep missing | — | — | unmeasured | — | — | infra | `ReactRenderWebViewTests` | M | WebKit flakiness under load |
| F9 | React natural line height | font pitch, rounded | correct | 1.3 | correct | unmeasured | (a) | emit the pitch | S | overlaps `Wo6Vni` |
| F10a | SwiftUI inner shadow on text | draws it | draws it | — | none | — | (a) | masked inner shadow | S–M | — |
| F10b | SwiftUI `fit_content` a pixel narrow | — | — | — | 1 px at 2x | 5.96 | (a) | find the rounding | S | — |
| F10c | SwiftUI themed number variables | — | — | — | dropped | — | (a) | theme numbers | M | low value |
| F10d | SwiftUI remote images | draws them | draws (cache) | `url()` | `AsyncImage`, done | — | (c) D4 | `AsyncImage` at draw time, not bundled (leaf `46XAVC`) | S | none — no network at generate time |
| F10e | SwiftUI justify | justified | justified | `text-align` | leading | — | (c) | accept + warning | — | — |
| F11 | Wrong documented causes | — | — | — | — | — | docs | correct in place | S | — |
| F12 | Test Plex face vs Pen's | variable (to confirm) | — | — | — | 4.9 implied | infra | confirm, maybe swap fonts | S | many gates move |

## Kept on purpose (class b, and rulings already made): not in the plan

- **Background blur below opacity 1.** Pen draws none (its opacity layer is read empty); Woodcase draws it. Ben's
  ruling, 2026-09-26, PenRendering.md.
- **Mesh colour rounding.** Pen truncates the blended vertex colour to 8 bits; Woodcase rounds once. Worth ≤ 1
  step; ruling 2026-09-26 (PenMeshGradients.md).
- **Mesh subdivision.** Pen's fixed 32 × 32 cells facet; Woodcase is adaptive (ruling on `OHdROl`).
- **Blur at a 4 px sigma.** Pen's kernel fits sigma 4.24; Woodcase keeps the exact Gaussian (≤ 5/255 at edges).
- **Underline and strikethrough.** Pen strips both from text; Woodcase draws them and `lint` warns (decision
  (2), 2026-09-26).
- **Connections.** Pen drops them on load; Woodcase draws a segment (PenRendering.md).
- **Browser nodes.** Pen draws a live snapshot; Woodcase draws a placeholder and React writes an `<iframe>`
  (rulings, 2026-09-26).
- **The auto-width text paint domain.** Pen's is 1–7 pt narrower than the box it reports; accepted as "node box"
  with a tolerance (decision (1), 2026-09-26).
- **SwiftUI background blur as a Material, and layout as idiomatic stacks.** Ben's rulings; the baselines say
  so.
- **Material Symbols names missing from Pen's table.** Pen's own Material name table (3,810 names, read from
  Pen.app's `app.asar`, 2026-09-27, leaf `6vLFNQ`) lacks names the font draws, `expand_more` and `expand_less`
  among them, and draws its `help` placeholder for them; Woodcase's table (4,211 names, every one of Pen's
  resolving to the same glyph) draws the real icon. Woodcase is better; not copied (PenIconFonts.md, *Which cut
  of the glyph*).

The **stroked-path offset** in PenInteroperability.md was presented as a Pen artifact Woodcase does not copy. It
is not a (b) item: the cause was wrong (F11).

## Decisions for Ben

> **Ruled by Ben, 2026-09-27:** D1 and D2 — ignore shaders and scripts for now (parked in
> [backlog.md](backlog.md); the phase-1 shader warnings stay). D3 — follow Pen's top width only
> "unless there's something more rational"; the integrator applies it to ellipses, polygons and paths
> alike, as one uniform centred stroke with a lint warning. D4 — SwiftUI loads remote images with the
> first-party `AsyncImage` rather than bundling them (leaf `46XAVC`).

- **D1 — Shaders: how far?** Options: warn only; CG CPU evaluator (L); React live WebGL (M); SwiftUI raster or
  MSL.
  - Recommendation: warn now (two-way, in the plan). Then the CG evaluator, React as live WebGL (revisiting
    2026-09-26 decision (4) for shaders only, since Pen is Chromium running the same GLSL), and SwiftUI as the
    baked raster.
  - Scope it by how often your files use shaders: the leaves are filed but gated on this answer.
- **D2 — Script nodes: run them?** Pen runs them headless, deterministically.
  - Recommendation: yes. Expand them in a `WoodcaseScripting` stage the CLI and viewer call, inline the result in
    the emitters, draw nothing on Linux, and probe Pen's PRNG before promising pixel parity.
  - Alternative: warn only.
- **D3 — Per-side widths on non-box shapes: follow Pen's "top only"?**
  - Recommendation: yes, and lint it. Woodcase's bands match nothing, and the format gives no other meaning.
    Filed as buildable. Say no if you would rather keep a Woodcase extension.
- **D4 — SwiftUI remote images: download at generate time and bundle?**
  - Recommendation: yes, the same path fonts take (network at generate, a warning when offline).
  - A licensing note, as with fonts: someone else's image goes into the package.
- **Accepted, confirm:** SwiftUI `justify` stays leading with a warning; background blur on SwiftUI text and
  groups stays undrawn under the Material ruling.

## Units of work and file overlaps

| Unit | Files it touches | Overlaps |
|---|---|---|
| U1 Google font faces (F3) | `GoogleFonts/GoogleFontResolver.swift`, `+Registration.swift`, `+Bundling.swift`, `GoogleFontMetadata.swift`, `PenGoogleFonts.md`, `GoogleFontResolverTests` | none; independent |
| U2 Rotated free nodes (F4) | `PenLayoutEngine.swift`, `PenLayoutEngine+FlexLayout.swift` (read only, to confirm flex stays), `Rendering/PenTransformBuilder.swift`, `CodeGen/SwiftUI/SwiftUINodeEmitter+Transform.swift`, `PenEngine.md`, `PenRendering.md`, layout goldens | SwiftUI render boards → after `T5l1ul` |
| U3 Icon placement (F5) | `Rendering/PenIconFontRenderer.swift`, the SwiftUI icon support template under `CodeGen/SwiftUITemplates/`, `PenIconFonts.md` | the SwiftUI template dir with U4 (different files) |
| U4 Per-side on shapes (F6) | `Rendering/PenStrokeRenderer+PerSide.swift`, `CodeGen/SwiftUI/SwiftUINodeEmitter+Stroke.swift`, the stroke support template, `ReactEmitter+SVGShapes.swift` / `+SVGStrokePaint.swift`, `Lint/` | React SVG files with U6 → sequence U4 before U6 |
| U5 React sweep (F8) | new `Tests/WoodcaseTests/ReactRenderWebViewTests.swift` (+ board list), `PenCodeGen.md` | none in Sources |
| U6 React effects (F7) | `ReactEmitter+Styles.swift`, `+Text.swift`, `+Icon.swift`, `+SVGShapes.swift`, `+Frame.swift` (`emitGroup`), goldens | `Wo6Vni` (text/icon), U4, U7 |
| U7 React line height (F9) | `ReactEmitter+Text.swift`, goldens | `Wo6Vni`, U6 |
| U8 SwiftUI text inner shadow + `fit_content` (F10a, F10b) | `SwiftUINodeEmitter+Effects.swift`, `+Text.swift`, `+Sizing.swift`, `SwiftUITemplates/PenSupport+Effects.swift` | `T5l1ul` (render boards); `+Text.swift` with nothing else here |
| U9 Shader warnings (F1 phase 1) | `Lint/` (new rule), CLI `render`/`shot` diagnostics, `ReactEmitter+PaintLayer.swift` (warning), `PenRendering.md`, `PenCodeGen.md`, `WoodcaseLint.md` | `Lint/` with U4 (separate rule files) |
| U10 Shader evaluator (F1 phase 2, D1) | new `Sources/Woodcase/Shader/` (GLSL front end and evaluator), `PenFillRenderer.swift`, `PenTextRenderer+Paint.swift`, `PenStrokeRenderer.swift` (the shader case) | after U9 |
| U11 Script nodes (D2) | `Sources/WoodcaseScripting/`, CLI pipeline, `ReactEmitter+Script.swift`, SwiftUI placeholder | the scripting host |
| U12 Docs (F11) | `PenInteroperability.md` | none |
| U13 Plex face check (F12) | `Tests/WoodcaseTests/Fonts`, `TestFontRegistration`, possibly gates | many gate files if the fonts swap; run it alone |
| U14 SwiftUI theme numbers (F10c) | `SwiftUINodeEmitter+Effects.swift`, `+Transform.swift`, `+Stroke.swift`, `SwiftUIGradient.swift` | U2 (`+Transform`), U4 (`+Stroke`), U8 (`+Effects`) → last |

Can run in parallel now: U1, U2, U3, U5, U9, U12. Then U4 and U8 (after `T5l1ul`), U6 and U7 (after `Wo6Vni` and
U5), and U13 alone. U10, U11 and U14 come later.

## Plan

```yaml
tasks:
  - title: Fidelity gaps — close where Woodcase draws differently from Pen
    desc: |
      From project/2026-09-27-fidelity-gaps.md (agent gaps). Each leaf cites its finding (F1–F12). Pen references for the new fixtures are committed in Tests/WoodcaseTests/Fixtures (render-font-faces, render-rotated-free, render-per-side-shapes, render-shader-fills, render-script-node), generated with scripts/pen-oracle --scale 2. scripts/png-mae ranks a woodcase shot against a Pen export outside the suite. Classification per Ben (2026-09-27): fix where Woodcase is wrong; keep ours where Pen is buggy (the "Kept on purpose" list is not work); ask Ben on design divergences (D1–D4).
    labels: [fidelity]
    children:
      - title: Google families draw every weight and style in the face the document asks for
        ref: fonts
        labels: [fidelity, cg, swiftui]
        desc: |
          F3. On a cold cache GoogleFontResolver.downloadRegularFace fetches only weight 400 normal; on a warm cache resolveCached (GoogleFontResolver+Registration.swift:92) registers the first .ttf in directory order and stops. So static families draw bold and italic in one arbitrary file (upright Instrument Serif renders italic today, because InstrumentSerif-Italic.ttf lists first), and variable families never fetch their separate italic file. Measured with woodcase shot + scripts/png-mae against render-font-faces.pen: plexmono-700 7.32, plexmono-italic 8.54, plexmono-700-italic 11.02, spectral-700 15.76, spectral-italic 14.07, inter-italic 13.82, lora-italic 14.81 (regular controls 2.2–2.5).

          Fix: resolve the (weight, style) faces a document uses; fetch each static face's file, and a variable family's italic file when italic is used; cache and register every file from its URL; replace the directory-order short-circuit with a per-face check; bundle the same set for SwiftUI (GoogleFontResolver+Bundling.swift). Test through an injected fetcher serving local files, never the network. Mind the gotcha: only one test per run may watch a family go from absent to present, so use families no other suite registers (IBM Plex Mono, Spectral and Lora are OFL; commit them, or renamed copies via scripts/rename-font-family). Update PenGoogleFonts.md.
        criteria:
          - A document using IBM Plex Mono at 700 and italic, rendered on an empty cache, registers the Bold, Italic and BoldItalic files and draws each board of render-font-faces.pen within MAE 3.0 of Pen's export.
          - With several faces cached for a family, every cached face is registered and a text's weight and style pick the right one (Instrument Serif regular draws upright).
          - A variable family used in italic fetches and registers its italic file (inter-italic and lora-italic within MAE 3.0).
          - woodcase generate swiftui bundles every face the document uses.
          - PenGoogleFonts.md describes per-face resolution.
      - title: A rotated node placed by x/y turns about its anchor in layout, CG and SwiftUI
        ref: rotation
        labels: [fidelity, layout, cg, swiftui]
        blockedBy: [T5l1ul]
        desc: |
          F4. Pen turns a node its parent does not lay out (layout none, or absolute) about its top-left x/y anchor. Its settled layout of render-rotated-free.pen's rectangle (200×60 at 80,60, rotation -20) is x 59.479, y 60, 208.46×124.79. Woodcase reports 80,60 with the same size: the box's corner is pinned at the anchor and CG pivots at the box's centre, so everything lands shifted. CG MAE (shot + png-mae): rrect 2.57, rtxtf 4.98, rtxta 4.98 (unrotated control 0.14). The existing render-text-fills-txt-rotated scores 7.33 in both CG and SwiftUI, the worst CG board in the repo. React already matches Pen (mkPpjZ, TransformPivot).

          Fix: offset the rotated bounding box's origin by the rotated corners' minimum relative to the anchor. Flex children keep today's rule, because Pen grows the slot. PenEngine.md states the wrong rule ("rotated bounding box anchored at the declared x/y"); correct it in place and say it was wrong. Adding SwiftUI render boards touches the batch support that T5l1ul owns.
        criteria:
          - Woodcase's layout of render-rotated-free.pen matches Pen's render-rotated-free.layout.json within 0.5 pt for every node.
          - CG renders rrect, rtxtf and rtxta within MAE 0.5 of Pen's exports, and render-text-fills-txt-rotated within 1.0.
          - SwiftUI renders the same boards within CG + 1.0.
          - Flex children, groups and every existing layout golden that has no rotated free node are unchanged.
          - PenEngine.md's rotated-container rule is corrected in place.
      - title: Icon glyphs are placed in their box the way Pen places them
        ref: icons
        labels: [fidelity, cg, swiftui]
        desc: |
          F5. icon-font-test is the worst gated CG board (5.25, PenIconFontSnapshotTests, gate 7.87). Ink boxes at 2x, Pen → CG: Material Symbols 48 pt y 44–115 → 47–119; Phosphor chat-dots-thin y 45–90 → 40–86; Lucide ellipsis 56–103 → 57–104. PenIconFontRenderer and SwiftUI's PenIconShape centre the glyph's ink, while Pen evidently places by font metrics, since the offset differs per library. icon-grad (1.66, the highest text-paint ceiling) is probably the same cause.

          First probe one glyph per library at two sizes and in a non-square box with scripts/pen-oracle, and commit the probe. Then fit the rule and apply it in both PenIconFontRenderer.swift and the SwiftUI icon support template.
        criteria:
          - A committed Pen-oracle fixture pins icon placement for each bundled library at two sizes and in a non-square box.
          - CG's icon-font-test MAE drops below 2.0 and its gate is tightened by the margin rule.
          - SwiftUI's parser-icon-font board gates at CG + 1.0.
          - PenIconFonts.md states Pen's placement rule.
      - title: A per-side stroke width on an ellipse, polygon or path draws as Pen draws it
        ref: perside
        labels: [fidelity, cg, swiftui, react, needs-ben]
        blockedBy: [T5l1ul]
        desc: |
          F6 / D3 (recommended yes). Pen draws a uniform centred stroke of the top width and ignores the other sides (render-per-side-shapes.pen: t12 r2 b6 l0 reaches 6 pt outside the ellipse; t2 r10 b4 l6 reaches 1 pt). Woodcase draws box bands clipped to the shape: MAE 15.56 ellipse, 15.30 polygon, 14.46 path. PenRendering.md calls this "not what Pen draws" and PenCodeGen.md "not established". Touches PenStrokeRenderer+PerSide.swift, SwiftUI's penSideBands (SwiftUINodeEmitter+Stroke.swift and the stroke template), React's SVG stroke, and a lint rule. Pen's choice of top looks arbitrary, so pin it with the fixture and say so in the docs.
        criteria:
          - CG draws all six render-per-side-shapes boards within MAE 0.5 of Pen's exports.
          - SwiftUI draws them within CG + 1.0 and React's SVG output strokes at the top width.
          - woodcase lint warns that only the top width counts on a non-box shape.
          - PenRendering.md and PenCodeGen.md describe the rule and cite the fixture.
      - title: React is measured against Pen on the renderer's fixture boards
        ref: reactsweep
        labels: [fidelity, react, tests]
        desc: |
          F8. Nothing renders React against render-shadows, render-background-blur, render-group-shadows, the gradient, mesh and line-height fixtures, the layout-* boards or the new fixtures, which is how F7 and F9 went unseen. Build ReactRenderWebViewTests, the React counterpart of SwiftUIRenderTests: emit each board, render it through WebViewTestHarness, record its MAE against Pen's PNG, gate at CG + 1.0 where React can match, and hold the rest to recorded baselines, each with its reason. Test code only; the suite is serialized and load-sensitive (see the WebKit gotchas).
        criteria:
          - A new suite renders at least the effects, gradient, mesh, line-height and layout-* boards in WebKit and records each MAE to performance/mae-test.csv.
          - Every board either gates at CG + 1.0 or has a recorded baseline with its reason.
          - PenCodeGen.md's verification section lists the suite and its figures, with the command that reproduces them.
      - title: React writes effects on text, icons, SVG shapes and groups, in Pen's order
        ref: reacteffects
        labels: [fidelity, react]
        blockedBy: [Wo6Vni, reactsweep]
        desc: |
          F7. emitEffects is reached only from frames, rectangles, CSS ellipses and browsers. A probe's text, icon, path and group shadows and blurs are emitted as nothing. Where effects are emitted: CSS paints the first box-shadow on top while Pen draws the array bottom first; a shadow's blendMode is dropped; a layer blur is truncated with Int(radius/2); two blurs write two filter keys; and a background blur is written on a node with no visible fill (Pen and CG draw none).

          Fix: text-shadow for text (cast by the glyphs); filter drop-shadow for icons and SVG shapes; a group's shadow over its content (an approximation of Pen's silhouette); mirror CG's rules as PenRendering.md lists them. Shares ReactEmitter+Text.swift and +Icon.swift with Wo6Vni, and the SVG files with the per-side leaf.
        criteria:
          - Text, icon, path, polygon, line, arc and group nodes emit their outer shadows and layer blur.
          - Shadows stack in Pen's order and keep their blend modes; blur radii keep their fractions; several blurs combine into one filter.
          - A node with no visible fill emits no backdrop-filter.
          - The React sweep gates render-shadows and render-group-shadows boards at CG + 1.0, or records why not.
      - title: React sets text with no lineHeight at Pen's natural pitch
        ref: reactlh
        labels: [fidelity, react]
        blockedBy: [Wo6Vni, reacteffects]
        desc: |
          F9. ReactEmitter+Text.swift writes lineHeight 1.3 "to approximate Core Text". Pen's natural pitch is the font's ascent + descent + leading, rounded to a whole point (Inter 16 pt → 19 pt, 1.19), which CG and SwiftUI both use via PenTextMeasurer.naturalLineHeight(of:). Emit that pitch in px at generate time, or line-height normal where the font is unknown. Goldens move; read them before committing.
        criteria:
          - A text with no lineHeight emits Pen's natural pitch for its font and size.
          - The React sweep's text-natural-line-height board gates at CG + 1.0.
          - PenCodeGen.md documents the rule.
      - title: SwiftUI draws inner shadows on text and fit_content text frames at Pen's width
        ref: swiftuitext
        labels: [fidelity, swiftui]
        blockedBy: [T5l1ul]
        desc: |
          F10a and F10b. Inner shadows on text are dropped with a warning; add a glyph-masked inner shadow to PenSupport+Effects.swift. Separately, SwiftUIStateRenderTests holds MoreLink 5.96, Chip-selected 4.68 and Chip 3.13 on the reason "its fit_content frame is a pixel narrower". Find the rounding (Pen's measured text width vs SwiftUI's frame) and fix it in SwiftUINodeEmitter+Sizing.swift or +Text.swift.
        criteria:
          - A text node's inner shadow renders within CG + 1.0 on a committed Pen-oracle board.
          - The Chip and MoreLink baselines drop to their text-antialiasing level (≤ 2.5) or record the measured cause.
          - The unemitted warning for inner shadows on text is gone.
      - title: Shader fills warn wherever Woodcase does not draw them
        ref: shaderwarn
        labels: [fidelity, lint, cli, react]
        desc: |
          F1, phase 1 (two-way). Pen runs shader fills (render-shader-fills.pen: uniforms, samplers, @sdf, @backdrop, @time = 0, and on text too). CG draws nothing (MAE up to 159 on the probe boards), React writes nothing without a warning, and `woodcase render` and `shot` say nothing. Add a lint rule, a render and shot diagnostic, and a React diagnostic, and state the gap in PenRendering.md and PenCodeGen.md, citing the fixture.
        criteria:
          - woodcase lint reports each shader fill with a message saying Woodcase does not draw it.
          - woodcase render and shot print one warning per document naming the shader nodes.
          - woodcase generate react warns for each shader fill it drops.
          - WoodcaseLint.md, PenRendering.md and PenCodeGen.md describe the gap.
      - title: CG runs shader fills (GLSL ES 1.00 on the CPU)
        ref: shadereval
        labels: [fidelity, cg, needs-ben]
        blockedBy: [shaderwarn]
        desc: |
          F1 / D1 — do not start until Ben answers D1. A GLSL ES 1.00 front end (lexer, parser, type checker) and a CPU evaluator compiled to Swift closures, in a new Sources/Woodcase/Shader/ folder (Foundation only, so it builds on Linux). Uniforms from annotations, @default and uniforms; @resolution in node points; @time 0; @mouse at the centre or 0 (decide by probe); a sampler2D image with bilinear filtering; @sdf as a signed-distance raster of the node's outline in resolution units with its gradient in gb; @backdrop from the capture the background blur uses; textureSize. Drawn through PenFillRenderer's clip/domain seam, so text, icons and strokes follow. Metal and WebKit were rejected: they fail headless (the Core Image gotcha). Expect 4–5 leaves (front end; evaluator and builtins; samplers and SDF; backdrop; integration), and measure the time per fill.
        criteria:
          - Every render-shader-fills board renders within MAE 1.0 of Pen's export.
          - A 400×200 shader fill at 2x renders in under 1 s in a release build, measured and recorded.
          - A shader that fails to compile draws nothing and reports the compiler error as a diagnostic.
          - The shader core imports only Foundation.
      - title: React draws shader fills live in WebGL
        ref: shaderreact
        labels: [fidelity, react, needs-ben]
        blockedBy: [shaderwarn, reactsweep]
        desc: |
          F1 / D1 — only if Ben chooses it, since it revisits 2026-09-26 decision (4) ("mesh and shader in React as raster") for shaders alone. Emit a PenShaderCanvas support component that compiles the .frag verbatim in WebGL 1 with its uniforms, @resolution, a live @time and @mouse. Warn for @backdrop, which cannot read the page behind an element. Bake @sdf at generate time. On text, draw it behind background-clip: text.
        criteria:
          - The React sweep renders render-shader-fills' uv-rect, checker and image boards within MAE 1.0 of Pen's export.
          - An @time shader animates in the preview.
          - A shader that reads @backdrop emits a warning.
      - title: Script nodes are expanded into their generated children
        ref: scripts
        labels: [fidelity, scripting, needs-ben]
        desc: |
          F2 / D2 — do not start until Ben answers D2. Pen runs a script node's JS headless (render-script-node.pen draws four red bars and the text 0.467327, byte-identical across runs; the generated children are in neither Pen's layout JSON nor its re-save). Expand script nodes before layout through the JavaScriptCore host (Sources/WoodcaseScripting), with the pencil object (width, height, input) and @input defaults, and inline the result in the emitters. First probe Pen's Math.random (sequences under different node ids and inputs) to identify the generator and its seed. It draws nothing on platforms without the host.
        criteria:
          - render-script-node.pen renders within MAE 1.0 of Pen's export.
          - Math.random reproduces Pen's sequence, or the docs record why it cannot.
          - React and SwiftUI emit the generated nodes in place of their placeholders.
      - title: PenInteroperability.md no longer blames a stroked-path offset on Pen
        ref: docs
        labels: [fidelity, docs]
        desc: |
          F11. The Stroked Path Positioning section says Pen rasterizes path and stroke into a bitmap and that this explains ~5.0 MAE on stroke-heavy fixtures. Commit 89e43e8 proved the 5.1 came from a stale 2026-03-23 reference: CG measures 0.027 against today's export. Correct the section in place as a marked correction that says the old cause was wrong. Docs only.
        criteria:
          - The section states the measured 0.027 and that the offset explanation was wrong, citing 89e43e8.
      - title: The suites draw IBM Plex Sans in the face Pen draws
        ref: plex
        labels: [fidelity, tests]
        desc: |
          F12, investigation first. The suites register static IBMPlexSans-{Regular,Medium,SemiBold}.ttf; the CLI's cache holds Google's variable IBMPlexSans[wdth,wght].ttf. With the variable face, woodcase shot + png-mae scores 0.55–1.96 on the layout-text-* boards; SwiftUIRenderTests' recorded CG + 1.0 gates imply 1.3–4.9 with the static faces. Establish which face Pen draws (glyph widths in its exports, or its font source). If it is the variable face, swap the committed test font (OFL) and re-tighten the affected gates by the margin rule. Run it alone, since it moves many gates.
        criteria:
          - The face Pen draws for IBM Plex Sans is established with evidence, in a dated note or in PenInteroperability.md.
          - If the test font changes, every affected gate is re-measured and tightened, with before and after figures recorded.
      - title: SwiftUI reads themed number variables in effects, rotation, gradient stops and per-side widths
        ref: swiftuinumbers
        labels: [fidelity, swiftui]
        blockedBy: [rotation, perside, swiftuitext]
        desc: |
          F10c, low priority. SwiftUINodeEmitter drops effect variables, rotation variables, gradient stop position variables and per-side stroke width variables with a warning, while colours already read through the theme. Read numbers through PenTheme the same way. Touches +Effects, +Transform, +Stroke and SwiftUIGradient, which is why it runs last.
        criteria:
          - Each of the four variable kinds emits a theme read instead of a warning.
          - A themed board renders within CG + 1.0 under two theme options.
```

The three `needs-ben` leaves (`shadereval`, `shaderreact`, `scripts`) are filed so the tree is whole. The
integrator should hold them until Ben answers D1 and D2. The per-side leaf is held for D3 too
(integrator, 2026-09-27: Pen's "top width only" looks arbitrary, so whether to copy it is Ben's call). D4 (SwiftUI remote images) is not filed: its leaf depends on the
answer.
