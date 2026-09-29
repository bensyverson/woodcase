# 2026-09-26 — How hard is it to render mesh gradients?

> Trimmed 2026-09-26 for publication: observed behavior and measurements only.

**Verdict: moderate, and easier than it looks.** Pen's algorithm is not a guess: a Swift port, drawn through CoreGraphics and built to match Pen's
observed output, hits headless Pen's PNG exports at **MAE 0.000** (max error one 8-bit step) on seven opaque test meshes at 1× and 2×. On a
translucent ellipse the MAE is 0.15, and on a deliberately folded mesh 0.01–0.05. The work that remains is engineering and a few decisions, not
research: a typed model, a CG-free tessellator and rasterizer, one renderer case, a lint check, and a choice for the React emitter. There CSS has no
equivalent. A small pre-rendered image measures well (MAE ≤ 0.7), but it bakes in the theme. Estimate: six Woodcase leaves, about two to three
agent-days in total, plus one RapidPro leaf. Leaf `lqP94J`, under `b3HCbu`. Inner shadow, background blur and the 1.2.14 compatibility questions are
in [the compatibility report](2026-09-26-pen-1.2.14-compatibility.md), not here.

## 1. What a `mesh_gradient` is, exactly

### The encoding (unchanged in 1.2.14)

`local/Pen-Schema-2.17.md:66-77` defines it, and `local/Pen-Format.md:28` lists it as a fill type:

```ts
/** Bezier-interpolated color grid, row-major. Keep edge points at default positions. */
{ type: "mesh_gradient"; enabled?; blendMode?; opacity?;
  columns?: number; rows?: number;
  colors?: ColorOrVariable[];                       // one per vertex
  points?: ( [number, number]                        // position, auto handles
           | { position: [number, number];
               leftHandle?, rightHandle?, topHandle?, bottomHandle?: [number, number] } )[] }
```

Pen 1.2.14 renders `mesh_gradient` fills the same way 2.17 did: the empirical check below, run against headless Pen's exports, reproduces the same
algorithm and the same output. The 1.2.14 version bump itself (to format `"2.19"`) is the compatibility report's subject, not this one.

There is **no per-patch data**. The mesh is a `columns × rows` grid of vertices. Each vertex has a position in unit space (`[0,1]²` over the node's width and height), a color, and four Bézier handles, which are *relative offsets* in the same unit space.

### Where the semantics come from

Pen.app is Electron, and its renderer is CanvasKit (Skia). The behavior below is stated as what Pen's exports show (§ The empirical check); where a
detail is not directly measurable from an export, it is marked (inferred).

- **Parsing (inferred).** Pen drops the whole fill if `rows`, `columns`, `points` or `colors` is missing, if `points.length ≠ colors.length`, or if
  `rows*columns ≠ points.length`. A bare `[x,y]` point, or an omitted handle, gets the default handles `left/right = ∓0.25/(columns−1)` and
  `top/bottom = ∓0.25/(rows−1)`. An unresolvable color becomes `#000000`.

  > **Measured 2026-09-26 (leaf `JXbZb2`).** A count mismatch removes the fill on load; `rows: 1` keeps it and paints
  > nothing; `#RGBA` colors paint nothing; a malformed point is repaired or kept, never refused. Table in
  > [what Pen drops from a file](2026-09-26-what-pen-drops-from-a-file.md); `woodcase lint` reports these as
  > `mesh-gradient-dropped` and `mesh-gradient-distorted`.
- **Tessellation.** Consistent with Pen's exports: the mesh is tessellated into a triangle mesh with per-vertex colors, at **32×32 cells per
  patch** (confirmed by the subdivision-count sweep below, which shows the port is exact only at 32).
- **Evaluation.** Consistent with Pen's exports: geometry is a bicubic tensor-product Bézier evaluation (§ The algorithm), and color easing is the
  smoothstep function `t²(3−2t)`.
- **Compositing (inferred).** The fill is drawn through an opacity/blend-mode layer, using vertex colors only, clipped to the fill path.
- **Serialization (inferred).** Positions and handles round to 1e-4 on save. A point is written as a bare `[x,y]` when all four handles equal the
  defaults within 1e-4, and otherwise each default handle is omitted individually. Headless re-save through `scripts/pen-oracle` also adds
  `"enabled": true`.

  > **Measured 2026-09-26 (leaf `K27BJ3`).** No longer inferred: `Tests/WoodcaseTests/Fixtures/mesh-point-elision.pen` and Pen's
  > re-save beside it (`scripts/pen-oracle`, `pen` CLI 0.3.9, format 2.19) pin the rule. A handle is dropped when both components
  > sit strictly within 1e-4 of the default, judged on the value **as written, before rounding** (a written `0.12514` on a `0.125`
  > default is kept and saved as `0.1251`; `0.1251` itself is dropped). Every surviving number rounds to four decimal places. A
  > single column or row takes the `max(n−1, 1)` divisor (a `columns: 1` mesh drops a `±0.25` left/right handle).
  > `PenMeshPoint.canonicalized(defaults:)` implements it and `PenMeshGradientFixtureTests` holds it to that file.

The `pen` CLI 0.3.5 is a separate engine bundle from Pen.app 1.2.14, and it still saves `version: "2.17"`. It produces the same 32-subdivision,
vertex-colored triangle output. The reference PNGs below come from the CLI's engine.

### The algorithm

For each patch with corners `TL, TR, BL, BR` (row-major neighbors), the renderer builds a 4×4 Bézier control net:

```
row 0:  TL            TL+TL.right         TR+TR.left          TR
row 1:  TL+TL.bottom  (TL+right)+(TL+bottom)−TL   (TR+left)+(TR+bottom)−TR   TR+TR.bottom
row 2:  BL+BL.top     (BL+right)+(BL+top)−BL      (BR+left)+(BR+top)−BR      BR+BR.top
row 3:  BL            BL+BL.right         BR+BR.left          BR
```

- **Geometry: a bicubic tensor-product Bézier patch.** It is not bilinear and not a Coons patch. The four interior "twist" points follow the parallelogram (zero-twist) rule shown above. `position(u,v) = B(v; B(u; row0), B(u; row1), B(u; row2), B(u; row3))`, scaled by the node's `width` and `height`.
- **Color: bilinear, not bicubic.** Each patch blends its four corner colors with eased parameters, `c = Σ corner · weight(S(u), S(v))`, where `S` is smoothstep. So color has zero derivative at every vertex, which is the "soft" look. Color is continuous across patch edges but not smooth. The blend is computed on **8-bit, unpremultiplied, sRGB-encoded** channel values (no linearization, no perceptual space) and truncated to integers. Skia then premultiplies each vertex and interpolates linearly across each triangle.
- **Color follows the parameters, not the position.** Moving a point warps the color field with it. The default handles are ¼ of a cell, not ⅓, so even an undistorted grid is not parametrized uniformly. A position→color shortcut such as `smoothstep(x)` is therefore wrong even for a 2×2 mesh.
- **Uncovered area is transparent, and folds overdraw.** Where handles or edge points leave part of the node uncovered, nothing is painted there. Folded triangles paint over earlier ones in row-major order. That is why the schema says "keep edge points at default positions".
- **The domain is the node's box** (`width × height`), clipped to the fill path. For a `path` node that box is not `path.boundingBox`, and Woodcase's linear gradients use `boundingBox` today.
- **Strokes can carry a mesh fill (inferred).** Pen's stroke fills use the same rendering path, with the stroke outline as the clip and the node's
  box as the domain.
- **Pen's own CSS/code export drops it (observed: exporting a node with a mesh fill produces no CSS for it).** Its fill-list swatch approximates the
  fill with a `linear-gradient(90deg, …)` of the unique colors: a thumbnail approximation, not a render.

### The empirical check

The fixture (Appendix A) has eight artboards. They cover a 2×2 mesh, a 3×3, a warped 3×3 with custom handles, a translucent `#RRGGBBAA` 2×2 at `opacity 0.7` inside an ellipse, curved handles on a 3×2, a black-to-white 2×2, an irregular 4×3, and a deliberately folded 2×2. Headless Pen rendered them:

```
scripts/pen-oracle <scratch>/lqP94J-probe/mesh.pen --out <scratch>/lqP94J-probe/out --scale 1,2   # sandbox off
```

The prototype `<scratch>/lqP94J-probe/meshproto.swift` (throwaway, about 300 lines) implements the port. It tessellates as above, then Gouraud-rasterizes the triangles into a premultiplied RGBA8 buffer using the top-left fill rule. It hands the buffer to CoreGraphics as a `CGImage` and draws it clipped to the shape, with `setAlpha(opacity)`. MAE uses the same arithmetic as `PenSnapshotTestHelpers.meanAbsoluteError`: sRGB, premultiplied RGBA8, the mean over all channels, 0–255.

```
swiftc -O meshproto.swift -o meshproto && ./meshproto mesh.pen out                  # sandbox off
MESH_N=8 ./meshproto mesh.pen out ; MESH_N=16 … ; MESH_LOWRES=1 … ; MESH_PERF=1 …
swiftc -O swiftuimesh.swift -o swiftuimesh && ./swiftuimesh mesh.pen out
```

| Artboard | Pen port, 32 subdiv (1× / 2×) | Color not eased (1× / 2×) | CG flat quads (1× / 2×) | SwiftUI `MeshGradient`, smooth (2×) |
|---|---|---|---|---|
| m2x2 | **0.000 / 0.000** | 11.33 / 11.33 | 6.26 / 4.54 | 0.86 |
| m3x3 | **0.000 / 0.000** | 9.83 / 9.85 | 17.42 / 9.01 | 2.53 |
| mwarp | **0.000 / 0.000** | 5.20 / 5.20 | 12.58 / 6.96 | 0.81 |
| malpha (ellipse, α) | **0.166 / 0.154** | 3.56 / 3.56 | 1.42 / 1.07 | n/a |
| mcurve | **0.000 / 0.000** | 13.00 / 12.99 | 11.68 / 6.67 | 1.52 |
| mbw | **0.000 / 0.000** | 11.75 / 11.79 | 17.63 / 7.89 | 0.44 |
| m4x3 | **0.000 / 0.000** | 7.50 / 7.50 | 17.56 / 9.49 | 3.16 |
| mfold | **0.050 / 0.011** | 7.90 / 7.86 | 3.55 / 2.11 | 7.14 |

The maximum per-channel error of the port is 0–1 on every opaque case. On malpha it is 27–49 at a handful of anti-aliased ellipse-edge pixels. On mfold it is 255 at a few fold-edge pixels, where Skia's non-anti-aliased triangle coverage and mine disagree about a pixel center. "Color not eased" keeps the Bézier geometry and drops the smoothstep. It shows the smoothstep carries 5–13 MAE on its own. That is the size of the error a plausible-but-wrong reading produces, and the project's snapshot threshold is 8.0.

The subdivision count is part of the look. At 32 the port is exact. At 16 its MAE is 0.10–0.73, at 8 it is 0.32–3.19, and at 4 it is 0.95–12.4 (`MESH_N=…`). Pen's 32-cell Gouraud facets are therefore what we must reproduce; a "smoother" analytic evaluation would *differ* from Pen by a fraction of a level.

The SwiftUI column is **evidence against a note from March**. [2026-03-28-codegen-feasibility-summary.md](2026-03-28-codegen-feasibility-summary.md) rates native `MeshGradient` as "Perfect". Fed Pen's positions and absolute handles (`BezierPoint`, `smoothsColors: true`, `.device`), it lands at MAE 0.4–3.2, and 7.1 on the fold. That is close, but it is Apple's color interpolation, not Pen's. (`smoothsColors: false` gives 5.4–13.0.) I have not edited that note, because the brief kept this leaf to one document. It wants a marked correction. (Made 2026-09-26, leaf `smbv2z`.)

## 2. What RapidPro does today

Nothing. `Sources/RapidPro/Conversion/PenFill+RenderFill.swift:75` returns `nil` for `.meshGradient`. `Tests/RapidProTests/Conversion/PenFillConversionTests.swift:193` pins that ("Mesh gradient returns nil (unsupported)"), and `Documentation.docc/RenderNodeGuide.md:65` documents it. There is no shader or tessellation code to reuse. RapidPro's [vision note](../../RapidPro/project/2026-04-07-rapidpro-vision.md) (§ Mesh Gradients, line 209) plans for "each patch is a bilinear interpolation in a fragment shader". §1 shows that plan is **wrong** on two counts: the geometry is bicubic, and the color is smoothstep-eased.

What *does* carry over is the shape of Pen's own GPU path: a CPU-tessellated vertex grid with per-vertex colors, drawn as plain triangles. That is exactly a Metal vertex buffer with Gouraud shading, and it needs no special shader. So the reusable piece runs the other way, from Woodcase to RapidPro. If the Woodcase tessellator is CG-free and returns `(positions, colors, indices)`, RapidPro can upload it unchanged.

## 3. CoreGraphics approaches

| Approach | Fidelity (measured) | Performance | PDF | Portability |
|---|---|---|---|---|
| **A. CPU tessellate (Pen's 32×32/patch) + Gouraud-rasterize to an RGBA buffer at device scale, draw as a `CGImage` clipped to the path** | **MAE 0.000** opaque, 0.15 translucent | Tessellation 1.1 ms. Raster **85 ms** for a 4×4 mesh at 2000×2000 px (unoptimized prototype, `MESH_PERF=1`). About 2–8 ms for the 200–320 pt fixtures at 2×. | Raster image XObject, which is **what Pen's own PDF export does** (below) | Tessellator and rasterizer are pure Swift. Only the final `CGImage` draw touches CG. |
| B. CG vector: fill every tessellated cell as a flat-color quad | MAE 2.1–17.6, with seams (anti-aliased cell edges) | 2k–10k `fillPath`s per fill | Stays vector but bloats the file, and PDF viewers show hairline seams | CG |
| C. `CGShading` / PDF type 6/7 shading | n/a | n/a | **Not available.** `CGShading.h` has only `CGShadingCreateAxial`/`Radial` (and their `…WithContentHeadroom` variants). CoreGraphics' PDF context cannot take a hand-written shading dictionary, so type 6/7 output would mean our own PDF writer or post-processing. | — |
| D. Core Image | n/a | — | Raster | No mesh-gradient filter exists (`CIMeshGenerator` strokes line segments). A custom kernel would need an inverse Bézier map per pixel: harder than A and not exact. |
| E. SwiftUI `MeshGradient` via `ImageRenderer` | MAE 0.4–3.2, 7.1 folded | GPU | Raster | macOS 15/iOS 18 only, `@MainActor`, links SwiftUI into the library, and uses Apple's interpolation, not Pen's |
| F. Metal | Exact if it draws A's vertex buffer | Fast | Raster | Apple-only. This is RapidPro's job, not the reference renderer's. |

**A is the recommendation.** It is exact because it *is* Pen's algorithm. Its pure-Swift core also serves the React emitter (§4) and RapidPro (§2). The 85 ms figure is a naive loop: it allocates a three-element array per pixel and computes barycentrics per pixel, not incrementally. An incremental scanline loop is standard and should be far faster, but I have **not measured** that. If needed, cache the rasterized buffer per `(fill, box size, scale)` for the viewer.

**Resolution.** Rasterize at the context's device scale, taken from `context.userSpaceToDeviceSpaceTransform`. The existing blur code uses `abs(context.ctm.a)`, `PenEffectRenderer.swift:208`. In a PDF context that scale is 1, and a 1× raster of a smooth gradient is soft but not wrong. Pen's own PDF export uses **2×**. `Export(['mA2x2','mCwarp'],'pdf',…)` through `pen interactive` wrote a 200×200 pt page carrying a `/Subtype /Image /Width 400 /Height 400` XObject, and a 240 pt page carrying 480×480, with no shading dictionaries. A floor of 2× for non-bitmap contexts matches Pen.

**How small can a raster be?** Render the mesh at a reduced size, then let CoreGraphics upscale it (`interpolationQuality = .medium`) to the 2× reference (`MESH_LOWRES=1`):

| Long side | MAE (opaque cases) | MAE (mfold) | PNG bytes |
|---|---|---|---|
| 32 px | 0.55–1.17 | 5.36 | 228–1,881 |
| 64 px | 0.33–0.68 | 2.68 | 264–5,414 |
| 128 px | 0.23–0.41 | 1.39 | 367–16,588 |

A mesh gradient is low-frequency, so a 64–128 px raster is visually lossless. That matters for PDF size and for §4.

**Adjacent gaps the implementation will trip over.**

- `PenRenderer.renderFillsEvenOdd` (`PenRenderer.swift:592`) draws only color fills, so gradients and meshes on even-odd paths are dropped today.
- `PenStrokeRenderer` uses only the first solid color (`PenStrokeRenderer.swift:133-141`), so stroke meshes (and stroke gradients) have nowhere to go.
- The renderer imports CoreGraphics unconditionally, so "cross-platform" applies to the model and the tessellator, not the renderer.

## 4. The React/HTML emitter

Today `ReactEmitter+Styles.swift:268` and `:289` return nothing for a mesh, so the element renders unpainted. That matches Pen's own code export. CSS has no mesh primitive. SVG 2's `<meshgradient>` was dropped from the spec and never shipped in a browser.

| Option | Fidelity | Cost | Themes/variables |
|---|---|---|---|
| **a. Pre-rendered PNG as a `data:` URI** `background-image` with `background-size: 100% 100%`, produced by the §3 core at 64–128 px | MAE ≤ 0.7 at 64 px (measured with CG's upscale, not a browser's; browsers' bilinear should be comparable, **unmeasured**) | Small. Emitter-only, no runtime. 0.3–5 KB per fill at 64 px. | Baked. A themed mesh needs one URI per theme, switched by the same selector mechanism the emitter uses for CSS variables. |
| b. Runtime component (`<MeshGradient>` on a canvas: WebGL triangles, or a software raster with `putImageData`) | Exact | A JS runtime file in the harness (~150 lines), tests in WebView | Live. It reads CSS variables at runtime. |
| c. Layered `radial-gradient`s, one per vertex | Poor on warps and folds (not measured) | Small | Live |
| d. Pen's behavior: emit nothing, or its swatch `linear-gradient` of unique colors | Wrong (swatch) or absent | None | — |

**My recommendation is (a)**, with one URI per theme when the colors are variables. It reuses the renderer's core, needs no runtime, and measures well. Choosing between (a), (b) and a fallback is a product call. See the open questions.

## 5. Everything else a full feature touches

- **Model.** `PenFill.PenMeshGradientFill.points` is `[AnyCodable]` (`Models/PenFill.swift:134-160`), and its doc says "unsupported in renderer". The house rule is strong typing, so it should become `[PenMeshPoint]`: an enum of `.position([x,y])` or `.handles(position:, left?, right?, top?, bottom?)` that round-trips the form it was written in. The file also holds five types; `PenMeshGradientFill` and `PenMeshPoint` want their own files. Missing `rows`, `columns` or `points` stays representable, because Pen writes and tolerates it.
- **Variable resolution.** `PenVariableResolver.swift:879-884` already resolves `enabled`, `opacity` and every color. It needs nothing more, unless `points` become variable-capable (they are not in the schema).
- **`woodcase schema` / refusals.** `PenFill+Schema.swift:60-80` describes `points` as "an array of control points, kept as written", `[any, …]`. That becomes the real shape: `[[x, y] | {position, leftHandle?, …}, …]`.
- **`set` / editing.** Fills are one whole-value property (`kind.fills`). Moving one mesh point means rewriting the whole fill JSON, through `set kind.fills='…'` or `woodcase js` (`doc.set`). That is the same for every fill kind today, and I'd leave it. Per-element paths into fills would be a general editing feature, not a mesh one.
- **Lint.** Add a new check, `mesh-gradient`, for three cases:
  - `rows*columns ≠ points.count` or `≠ colors.count`, or a missing field. Pen *silently drops the fill*, and Woodcase must too.
  - `columns` or `rows` < 2. Pen's defaults divide by `max(n−1,1)`, and the tessellator then builds zero patches, so it paints nothing.
  - Edge points moved off the boundary, or handles that fold the mesh. Uncovered area goes transparent, as the schema's advice warns.

  The catalog, `LintFormatter+Catalog.swift`, and the docs follow.
- **Viewer.** It serves `PenRenderer` PNGs and has no fill inspector, so it gets meshes for free. The render cache already keys on document state.
- **PDF export.** Handled through the renderer (§3 Resolution). Add a test asserting the PDF carries an image XObject.
- **Docs.** `PenRendering.md:69` ("…the same as a mesh gradient"), `EditingDocuments.md:135`, the `PenFill` doc comment, and the `PenFillRenderer` comment at `:9`/`:58`. RapidPro's `RenderNodeGuide.md:65` and its vision note belong to the RapidPro leaf.
- **Fixtures.** Commit Appendix A as `Tests/WoodcaseTests/Fixtures/render-mesh-gradients.pen` with `pen-oracle` PNGs, and its canonical re-save as a round-trip golden. Tests read the files only; they never call `pen`.

## 6. Proposed leaves

| # | Leaf | Files | Criteria | Size |
|---|---|---|---|---|
| 1 | **Typed mesh model** | `Models/PenFill.swift` → split out `PenMeshGradientFill.swift`, new `PenMeshPoint.swift`; `PenFill+Schema.swift`; resolver compile-fix; tests | Bare vs object points round-trip in the form written. Default-handle elision matches Pen's serializer (1e-4). Pen's canonical re-save of the fixture round-trips byte-equal through Woodcase. `woodcase schema frame` prints the point shape. DocC 100%. | S–M |
| 2 | **CG-free tessellator + rasterizer** | new `Rendering/Mesh/PenMeshTessellator.swift`, `PenMeshRasterizer.swift` (pure Swift, no CG import); tests | Exact port of §1 (32 subdivisions, smoothstep bilinear color on 8-bit sRGB, truncation, parallelogram twists). Pen's drop rules are expressed as a validation result. Vertex positions and colors are unit-tested at known parameters. Top-left rule: no double-drawn shared edges (a translucent seam test). | M |
| 3 | **Renderer integration** | `PenFillRenderer.swift`, `PenRenderer.swift` (even-odd branch), `PenRendering.md`; fixture + `pen-oracle` PNGs; snapshot test | Draws in the node's box, clipped to the path (non-zero and even-odd), with opacity and blend mode. Device-scale raster with a 2× floor for PDF. MAE ≤ 0.5 against every fixture PNG at 1× and 2× (measured 0.000–0.17). The PDF test finds an image XObject. Docs updated. | M |
| 4 | **Lint `mesh-gradient`** | `Lint/DocumentLinter+MeshGradient.swift`, catalog, docs | Flags count mismatch or missing fields (states that Pen drops the fill), rows/columns < 2, moved edge points or folds. Red/green tests per case. | S |
| 5 | **React emitter** (shape per Q2) | `ReactEmitter+Styles.swift`, goldens (component + page) | Per the ruling. If (a): a `background-image` data URI from leaf 2 at the chosen size, per-theme URIs for variable colors, goldens regenerated and read. | S (a) / M (b) |
| 6 | **Docs sweep** | `PenFill` doc comment, `EditingDocuments.md`, `PenRendering.md`, `WoodcaseEditor.md` example if wanted; correction block in the 2026-03-28 feasibility note | No stale "unsupported" claims. The SwiftUI "Perfect" claim is corrected in place. | S |
| R | **RapidPro: mesh via the Woodcase tessellator** (sibling repo) | `PenFill+RenderFill.swift`, a vertex-color pipeline, `RenderNodeGuide.md`, vision-note correction | Uploads leaf 2's grid as a Metal vertex buffer. MAE against the same fixture PNGs. | M |

Order: 1 → 2 → 3, with 4 in parallel with 2. Leaf 5 waits on Q2. Leaf 6 goes last. Leaf R needs 2 published.

**Risks.**

- *Provenance* (Q1).
- *Skia edge-pixel coverage* on folds and on translucent anti-aliased clips: the reason malpha and mfold are not 0.000. It is harmless under the 0.5 threshold, but a pixel-probe test at a fold edge would be brittle.
- *Pen may change the algorithm* (subdivision count, easing). The pinned fixture PNGs would catch it on the next `pen-oracle` regeneration.
- *Performance on huge artboards* until the rasterizer is incremental.
- *Semantics of the node box vs path bounds* for `path` nodes with a `viewBox`: this is untested. The fixture should add a path case.

## Open questions for Ben

> **Rulings (Ben, 2026-09-26).** Learning from Pen's shipped code is acceptable, but improve on it wherever possible rather than taking it as gospel; visual parity matters. React: a pre-rendered raster. PDF: rasterize at 2×. Pen's quirks (count mismatch, `#RGBA`) are flagged in lint so Woodcase never writes files Pen renders badly; the faceting should be improved on if better output is possible. Strokes and text go to the backlog. The RapidPro leaf follows once Woodcase's implementation works as a reference.

1. **Provenance.** This algorithm was read from Pen's own installed application, not derived solely from black-box exports. Is porting its
   *behavior* acceptable? The math is textbook: tensor Bézier patches plus smoothstep. Or should the implementing agent re-derive it black-box from
   `pen-oracle` exports only? The MAE fixtures validate either route, but a clean-room derivation costs an extra leaf.
2. **React.** Choose one: (a) a pre-rendered data-URI raster with themes baked per theme, (b) an exact runtime canvas/WebGL component, (c) a layered-radial approximation, or (d) Pen's own behavior of emitting nothing.
3. **PDF.** Is a 2× raster (Pen's choice) right? Or should it be a fixed DPI (e.g. 300), or the vector flat-quad option, which measured badly and seams?
4. **Quirk parity.** Should Woodcase copy Pen where Pen is arguably wrong? That covers dropping the whole fill on a count mismatch, `#RGBA` (4-digit) colors decoding to transparent black in the mesh path (Pen's color parser accepts only 3/6/8-digit hex forms), and the 32-cell Gouraud facets. My default would be yes, plus a lint finding.
5. **Scope.** Should mesh fills on **strokes** and **text** be included, or backlogged? Both need the stroke and text renderers to learn non-solid fills first, and gradients are missing there too.
6. **RapidPro.** Now (leaf R), or when RapidPro next touches fills?

## What I could not do

- **Browser-side MAE for option (a).** I did not measure a browser's upscale of a data-URI raster. The CG upscale stands in for it.
- **The app's own engine.** Per the coordinator's instruction, I did not drive Pen.app or its MCP Export. Every reference PNG is from the `pen` CLI 0.3.5 headless engine, which is not the 1.2.14 app bundle (it still saves 2.17). The mesh code in both bundles has the same structure, but an app-rendered PNG would close that gap.
- **Throwaway code.** The prototype and fixture live in the session scratchpad (`lqP94J-probe/`) and will not survive it. The fixture is reproduced below, and §1 is the algorithm, so leaf 2 can rebuild both. `scripts/` was out of bounds for this leaf.

## Appendix A — the probe fixture

Save as `mesh.pen` and run `scripts/pen-oracle mesh.pen --out out --scale 1,2`, with the sandbox off and `pen` logged in. The ellipse's parent needs `"layout":"none"`. Without it, the frame's default horizontal layout ignores the ellipse's `x`/`y`, and a first run compared a misplaced shape (MAE 13.5, not a mesh error).

```json
{"version": "2.17", "children": [
  {"type":"frame","id":"mA2x2","name":"m2x2","x":0,"y":0,"width":200,"height":200,"fill":{"type":"mesh_gradient","columns":2,"rows":2,"colors":["#FF0000","#00FF00","#0000FF","#FFFF00"],"points":[[0,0],[1,0],[0,1],[1,1]]}},
  {"type":"frame","id":"mB3x3","name":"m3x3","x":300,"y":0,"width":240,"height":180,"fill":{"type":"mesh_gradient","columns":3,"rows":3,"colors":["#FF0000","#FF8800","#FFFF00","#00FF88","#FFFFFF","#0088FF","#8800FF","#000000","#FF00AA"],"points":[[0,0],[0.5,0],[1,0],[0,0.5],[0.5,0.5],[1,0.5],[0,1],[0.5,1],[1,1]]}},
  {"type":"frame","id":"mCwarp","name":"mwarp","x":600,"y":0,"width":240,"height":240,"fill":{"type":"mesh_gradient","columns":3,"rows":3,"colors":["#1E3A8A","#1E3A8A","#1E3A8A","#1E3A8A","#F472B6","#1E3A8A","#FACC15","#1E3A8A","#10B981"],"points":[[0,0],[0.5,0],[1,0],[0,0.5],{"position":[0.3,0.7],"leftHandle":[-0.2,0.1],"rightHandle":[0.2,-0.1],"topHandle":[0.05,-0.3],"bottomHandle":[-0.05,0.3]},[1,0.5],[0,1],[0.5,1],[1,1]]}},
  {"type":"frame","id":"mDfrm","name":"malpha","x":900,"y":0,"width":200,"height":200,"fill":"#FFFFFF","layout":"none","children":[{"type":"ellipse","id":"mDell","name":"ell","x":10,"y":20,"width":180,"height":160,"fill":{"type":"mesh_gradient","columns":2,"rows":2,"opacity":0.7,"colors":["#FF000000","#00FF00FF","#0000FF80","#FF00FFFF"],"points":[[0,0],[1,0],[0,1],[1,1]]}}]},
  {"type":"frame","id":"mEcrv","name":"mcurve","x":1200,"y":0,"width":300,"height":150,"fill":{"type":"mesh_gradient","columns":3,"rows":2,"colors":["#000000","#FFFFFF","#000000","#FFFFFF","#000000","#FFFFFF"],"points":[[0,0],{"position":[0.5,0],"bottomHandle":[0.25,0.4]},[1,0],[0,1],{"position":[0.5,1],"topHandle":[-0.25,-0.4]},[1,1]]}},
  {"type":"frame","id":"mFbw","name":"mbw","x":1600,"y":0,"width":256,"height":64,"fill":{"type":"mesh_gradient","columns":2,"rows":2,"colors":["#000000","#FFFFFF","#000000","#FFFFFF"],"points":[[0,0],[1,0],[0,1],[1,1]]}},
  {"type":"frame","id":"mG4x3","name":"m4x3","x":2000,"y":0,"width":320,"height":200,"fill":{"type":"mesh_gradient","columns":4,"rows":3,"colors":["#0F172A","#7C3AED","#DB2777","#F59E0B","#0EA5E9","#FFFFFF","#22C55E","#EF4444","#111827","#FDE047","#6366F1","#14B8A6"],"points":[[0,0],[0.3333,0],[0.6667,0],[1,0],[0,0.5],[0.45,0.35],{"position":[0.6,0.7],"rightHandle":[0.15,0.2],"leftHandle":[-0.1,-0.05]},[1,0.5],[0,1],[0.3333,1],[0.6667,1],[1,1]]}},
  {"type":"frame","id":"mHfld","name":"mfold","x":2400,"y":0,"width":200,"height":200,"fill":{"type":"mesh_gradient","columns":2,"rows":2,"colors":["#FF0000","#00FF00","#0000FF","#FFFF00"],"points":[{"position":[0,0],"rightHandle":[1.2,0.6],"bottomHandle":[0.6,1.2]},[1,0],[0,1],{"position":[1,1],"leftHandle":[-1.2,-0.6]}]}}
]}
```
