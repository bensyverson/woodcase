# Pen's geometry model, and what Woodcase's rects should mean

2026-09-28 · leaf `w2er6i` · for Ben to rule on

**Answer in one paragraph.** Pen's layout sees exactly one thing per node: its **box**
(`0,0,width,height`) carried into the parent by its **transform** (translate to `x`,`y`,
turn and flip about that anchor), and the parent lays out the **bounds** of that turned box.
Strokes, shadows, layer and background blur never enter layout — not for flex slots,
siblings, `fit_content` parents or group unions, turned or not, and not even when the
container sets `layoutIncludeStroke: true`. Those belong to a third extent, the **painted
extent**, which Pen uses only to size exports, cull drawing and hit-test a stroke band.
Woodcase already keeps the first two correctly for every case but one (a turned
`fill_container` child), and has no single notion of the third. The proposed model names
all three, keeps `PenRect` as the bounds, and adds the painted extent as one library
function every consumer reads.

## Evidence

### How it was measured

```sh
scripts/gen-geometry-probe <scratch>/geometry-probe.pen
scripts/pen-oracle <scratch>/geometry-probe.pen --out <scratch>/pen --scale 2   # sandbox off
woodcase tree <scratch>/geometry-probe.pen --json > <scratch>/woodcase-tree.json   # sandbox off
scripts/layout-diff <scratch>/pen/geometry-probe.layout.json <scratch>/woodcase-tree.json
woodcase shot <scratch>/geometry-probe.pen <board> --scale 2 --out <scratch>/wc/<board>.png
scripts/png-mae <woodcase png> <pen png, cropped to the board>
```

`pen` CLI 0.3.9 (the engine `pen-oracle` drives; its obfuscated `index.mjs` has the same
`layoutPositionToLocalPosition` and group bounds code as Pen.app's). The probe run lives in
the session scratchpad (`w2er6i-probe/`), not in the repo: the generator reproduces it.
Every stroke is 12 pt `#00AA0099` unless noted; every leaf is a 60×40 rectangle; per-side
is `{top 4, right 16, bottom 24, left 8}`; the shadow is offset (10, 10), blur 8, spread 4.

### Pen's own code (Pen.app `app.asar` → `out/editor/assets/index.js`, read-only)

Evidence of intent, each confirmed by the probe below.

- **A node's box is its size, nothing else:**
  `computeLocalBounds(e){e.set(0,0,this._properties.resolved.width,this._properties.resolved.height)}`
- **Its transform is anchored at `x`/`y`, pivot (0, 0):**
  `this._localMatrix.setTransform(…x+this._visualOffset[0],…y+this._visualOffset[1],0,0,…flipX?-1:1,…flipY?-1:1,…rotation??0,0,0)`
- **What layout (and `ctx.bounds`, and so `layout.json`) reports is the box through that
  transform:** `getTransformedLocalBounds(){…copyFrom(this.localBounds()),…transform(this.getLocalMatrix())…}`
  and `layoutGetOuterBounds(){return this.getTransformedLocalBounds()}`; the flex passes
  (`cie` fit-content, `uie` fill, `qBe` arrange) read only `layoutGetOuterSize()`,
  `layoutGetInnerSize()` (box minus padding) and commit through
  `layoutPositionToLocalPosition(e,n){const r=this.getTransformedLocalBounds(),i=this.getLocalMatrix().apply({x:0,y:0}),s=e-r.minX+i.x,o=n-r.minY+i.y;return{x:s,y:o}}`
  — a slot's corner is the bounds' corner, turned back into an anchor.
- **A group's box is the union of its children's turned boxes:**
  `computeLocalBounds(e){if(this.children.length){e.reset();for(const n of this.children)…e.unionBounds(n.getTransformedLocalBounds())}…}`
- **`layoutIncludeStroke` is parsed and ignored.** It is read (`this.layout.includeStroke=this._properties.resolved.layoutIncludeStroke??!1`),
  validated, saved and imported from Figma's `bordersTakeSpace`, but no layout function
  reads `layout.includeStroke`.
- **The painted extent is separate** — `getVisualLocalBounds` — box ∪ stroke path bounds
  (`bv(strokeFills)&&this.strokePath.unionBoundsInto(this.getFillPath(),e)`) ∪ unclipped
  children's visual bounds through their transforms, then effects:
  `function ME(t,e){…for(const r of t){if(!r.enabled||r.type!==1)continue;const i=Ld(r.radius)*3,s=r.offsetX,o=r.offsetY;e.unionRectangle(n.minX+s-i,…)}for(const r of t)!r.enabled||r.type!==2||e.inflate(Ld(r.radius)*3)}`
  with `Ld(t)=t/2`: a shadow adds its offset rect ± 1.5·blur (spread is **not** counted), a
  layer blur inflates by 1.5·radius, a background blur adds nothing.
- **The painted extent's consumers:** raster/PDF export size (`c.unionBounds(x.getVisualWorldBounds())`),
  render culling (`if(i<=0||!n.intersects(this.getVisualWorldBounds()))return`), and hit
  testing, which accepts the turned box first and the stroke band second:
  `if(this.containsPointInBoundingBox(r,i))return this;if(!this.getVisualWorldBounds().containsPoint(r,i))return null;…this.strokePath.containsPoint(…)`.
  Overlap checks use the layout bounds (`overlapsNode` → `getWorldBounds`).

### 1–2. Stroke, shadow and blur never enter layout

Pen's `layout.json` (parent-relative; B is the middle child of a `fit_content` horizontal
row, padding 10, gap 10). Every row is identical to the unstroked control, and Woodcase
matches every one to 0.01 pt.

| Row | B carries | Row rect (w×h) | B rect | C.x |
|---|---|---|---|---|
| f00 | nothing (control) | 220×60 | 80,10 60×40 | 150 |
| f01–f03 | 12 pt inner / center / outer | 220×60 | 80,10 60×40 | 150 |
| f04 | per-side outer (4/16/24/8) | 220×60 | 80,10 60×40 | 150 |
| f07 | outer + flipX | 220×60 | 80,10 60×40 | 150 |
| f09 / f10 / f11 | shadow / blur 10 / background blur 10 | 220×60 | 80,10 60×40 | 150 |
| f13 | outer, row has `layoutIncludeStroke: true` | 220×60 | 80,10 60×40 | 150 |
| f14 / f15 | row itself stroked outer / inner, `layoutIncludeStroke: true` | 220×60 | children unmoved | 150 |
| f05 | outer + 30° | 231.96×84.64 | 80,10 71.96×64.64 | 161.96 |
| f06 | outer + 90° | 200×80 | 80,10 40×60 | 130 |
| f08 | outer + 30° + flipY | 231.96×84.64 | 80,10 71.96×64.64 | 161.96 |
| f12 | shadow + 30° | 231.96×84.64 | 80,10 71.96×64.64 | 161.96 |

71.96×64.64 is the bounds of the 60×40 box turned 30° (60·cos30 + 40·sin30, …) — the
turned box, with no stroke in it. An outer 12 pt band on that turned box reaches 16.4 pt
past those bounds at its mitered corners, and none of it is allocated.

Groups (board `groups`, rects parent-relative, group children relative to the anchor):

| Group | Second child | Pen group rect | Second child rect |
|---|---|---|---|
| g1 | outer stroke | 40,40 140×40 | 80,0 60×40 |
| g2 | shadow | 260,40 140×40 | 80,0 60×40 |
| g3 | outer stroke + 30° | 480,10 151.96×70 | 80,−30 71.96×64.64 |
| g4 | (group itself 30°) | 40,130 141.24×104.64 | 80,0 60×40 |
| g5 | (group itself flipX) | 120,200 140×40 | 80,0 60×40 |
| g6 | outer stroke + flipY | 480,160 140×80 | 80,−40 60×40 |

Free children (board `free`, anchor in parentheses): r1 outer (40,40) → 40,40 60×40;
r2 outer 30° (180,40) → 180,10 71.96×64.64; r3 outer 90° (320,40) → 320,−20 40×60;
r4 outer flipX (460,40) → **400**,40 60×40; r5 outer 30° flipY (600,40) → 580,−24.64;
r7 shadow 30°, r8 ellipse outer 30° → 71.96×64.64. The turn and flip pivot at the anchor
(r4 lands left of its `x`, r3 above its `y`), as the 2026-08-29 gotcha settled. Woodcase
matches all of these to 0.01 pt.

### 3. What Pen's layout reports for turned and flipped nodes

The bounds of the box through the anchor transform — never the unturned box, never the
painted extent. A turned flex child's **slot is the turned box's bounds**, placed by its
corner; alignment uses the same bounds (f17 `alignItems: center`: A and C at
y = 10 + (64.64 − 40)/2 = 22.32; f18 `justifyContent: end`: A at 78.04). Flip changes no
size and, in flex, no position (f07, f19).

### 4. Text and icons

The box, not the ink: text "Hg" Inter 32 settles 44×39 and turned 30° 57.61×55.77
(= 44·cos30 + 39·sin30); a lucide icon 32×32 turned 30° is 43.71×43.71, at 45° + flipX
45.25×45.25. Woodcase matches all eight rows (board `texts`).

### 5. Other ways painted extent differs from the layout rect

Pen's export of a top-level node is its painted extent (scale 2, pixels):

| Node | Layout rect | Pen export | Painted extent it implies |
|---|---|---|---|
| x1 outer 12 + shadow | 100×60 | 296×216 | stroke −12…112, then shadow (+10) ± 12 → 148×108 pt |
| x2 outer 12 + 30° | 116.60×101.96 | 299×270 | the 124×84 stroked box turned → 149.4×134.8 pt |
| x3 blur 10 | 100×60 | 260×180 | inflated 15 → 130×90 pt |
| x4 center 12 | 100×60 | 224×144 | inflated 6 → 112×72 pt |

Also: an unclipped frame's painted extent includes its children's (the `free` export is
1488×803 px for a 720×360 board, because r5's mitered band reaches 41.5 pt above it and
r6's flipped per-side band 24 pt left of it); a clipping frame's does not; per-side bands
flip with the node (r6's 24 pt left side paints on the right).

> **Added 2026-09-28 (leaf `Wkr2Pd`):** Pen frames the export on the painted extent's
> *exact* corner and rounds only the pixel size up (`ceil(extent × scale)`); it does not
> snap the corner to a pixel. Framed that way, `PenLayoutEngine.paintedExtent` reproduces
> all six export sizes here and the renders score MAE `free` 0.229, `groups` 0.045,
> x1 0.045, x2 0.035, x3 0.486, x4 0.000 (`swift test -j 3 --filter
> PenPaintedExtentProbeTests`); snapping the corner outward instead scores `free` 1.073,
> which is the "half-pixel crop misalignment" in the `free` figure below.

> **Added 2026-09-28 (leaf `slxqjU`):** §4's "the box, not the ink" is the *layout* rect
> only (extents i and ii); the painted extent (iii) does count a text's ink, matching
> Pen's own `computeVisualLocalBounds` override for its text class, which returns its
> Skia fill path's tight bounds (`app.asar`'s `out/editor/assets/index.js`, the class whose
> constructor calls `super(e,"text",n)`) rather than the box every other override reads.
> `PenLayoutEngine.textInkBounds(of:box:)` lays out the same lines `PenTextRenderer` draws
> and unions each line's Core Text image bounds (`CTLineGetImageBounds`). Three new
> top-level probes (x5 an unbreakable word wider and taller than its fixed box, x6 an
> italic whose slant reaches past the upright box, x7 a paragraph that wraps past its
> fixed height) hold Woodcase's grown-to-whole-pixel size to within 20 px of Pen's 2x
> export — not to the pixel, the way x1–x4 are: Core Text and Skia disagree on Inter's
> exact glyph metrics at these sizes even with optical sizing off (`PenGoogleFonts.md`,
> `PenTextOpticalSizeTests`), a font-rendering-engine gap this does not close. Measured
> gaps were 4–15 px; the box this replaced missed by 3–131 px on the same three boards
> (`PenPaintedExtentProbeTests`, `swift test -j 3 --filter PenPaintedExtentProbeTests`).

> **Added 2026-09-28 (later, leaf `slxqjU`):** an icon's painted extent is ink too. Pen's
> icon class (`DJt`) overrides `computeVisualLocalBounds` to return `fillPath.bounds` —
> its vector glyph, fitted to the box by its *shorter* side and centered, then measured
> tightly (`getIconPath`'s own path, not a font run) — not the box.
> `PenLayoutEngine.iconInkBounds(of:box:)` reuses the exact Core Text glyph
> `PenIconGlyph`/`PenIconFontRenderer` already draw and measures its image bounds. x8 (a
> star in a 60×20 box, far wider than the fitted glyph) holds to Pen's 2×
> export within 15 px (37×36; box-based missed by 60–170 px). x9 (a "minus" glyph in a
> square 40×40 box) widens the font-substitution gap a lot further — measured height 44
> px against Pen's 7 — read as Woodcase's installed Lucide font drawing a visibly taller
> glyph for that name than Pen's bundled vector icon, not a geometry bug; it is pinned
> only on direction (narrower than the box on both axes) rather than to a number.
>
> **Pending as of this note:** `PenLayoutEngine.ownInk(of:box:)` made public, and a new
> `PenLayoutEngine.strokeBandContains(_:of:box:) -> Bool` added for Penumbra's selection
> (hits the true stroked outline — `path.copy(strokingWithWidth:...)`, the same geometry
> `PenStrokeRenderer` paints with — not `ownInk`'s bounding rect of it). Both compile and
> are hand-verified geometrically (`PenStrokeBandHitTestTests`: a rect at each alignment,
> a rounded corner, an ellipse, a line's caps), but a sustained build-environment failure
> (nine consecutive `error: fatalError` builds over ~2 hours; see `project/gotchas.md`,
> "Escalated 2026-09-28") meant no test run of this suite — or of the new
> `PaintedExtentWalkTests` performance measurement — actually completed. Both need a
> confirming run once the shared machine's disk pressure clears.
>
> **Corrected 2026-09-28 (integrator):** the "build-environment failure" was not disk
> pressure: `PenStrokeBandHitTestTests.swift` did not compile (`#expect(…, cap)` passing a
> `String` for a `Comment`), and `--quiet` shows a compile error only as a bare
> `fatalError`. Fixed at integration; all 8 stroke-band tests and the icon and text probes
> then passed on their first run. `PaintedExtentWalkPerfTests` (`swift test -j 3 --filter
> PaintedExtentWalkPerfTests`, debug build, quiet machine): 974 nodes of `woodcase-app.pen`,
> `paintedExtent` once per node, **min 39.1 ms** (five samples 39.1–51.9 ms); no before
> figure was taken.
>
> **Corrected 2026-09-28 (integrator):** x9's gap was not the Lucide font. Woodcase draws
> the "minus" as a bar about 26 × 2.5 pt, as Pen does (`woodcase shot … x9 --scale 4`);
> `CTLineGetImageBounds` without a context reported 33.5 × 22 for it. `iconInkBounds` now
> unions the glyph outlines (`CTFontCreatePathForGlyph`, what Pen's `fillPath.bounds`
> measures), and x8 and x9 both land within 4 px of Pen's exports. `textInkBounds` uses the
> same measure; for Inter it changes nothing (x5–x7 off by the same 2–15 px either way).

### Woodcase against Pen

`scripts/layout-diff`: **156 rects compared, 10 differ**, all in three rows:

| Row | Case | Pen (first layout) | Pen after a relayout | Woodcase |
|---|---|---|---|---|
| f16 | B `width: fill_container`, 30°, row width 300 | B 141.24×104.64, row h 124.64, C.x 231.24 | same | B **140×40**, row h **60**, C.x 230 |
| f20 | B `height: fill_container`, 90°, row h 120 | B 100×60, row w **160** | row w 260 | B **100×100** (drawn 20 pt low), row w 260 |
| f21 | a turned `fit_content` frame | row w **211.96** | row w 231.96 | row w 231.96 |

(The `flex` board's own height differs by f16's 64.64.) "After a relayout" is the same
session with each row's `gap` set to 11 and back to 10 (`pen interactive`, three `Get`s).

Paint: where layout agrees, Woodcase's `shot` matches Pen's export — `scripts/png-mae`
0.815 on flex rows f00–f15, 0.187 `groups`, 0.204 `texts`, 0.902 `free` (Pen's exports
cropped to the board at their measured overflow offset; the `free` figure includes a
half-pixel crop misalignment). Stroke bands overlap siblings identically, per-side bands
flip identically, and `layoutIncludeStroke` rows paint identically. Uncropped, x1–x4 score
27–81 only because `shot` frames the layout rect while Pen frames the painted extent;
cropped to the layout rect x1 and x4 score 0.000 and x3 0.485.

## Divergences

1. **Bug — a turned `fill_container` child on the main axis (f16).** Pen gives the fill
   share to the child's *unturned* width, then allocates the bounds of the turned result;
   the row grows and later siblings move. Woodcase's `absorbFill`
   (`PenLayoutEngine+FlexLayout.swift`) takes the filled size raw, so the slot is the
   unturned 140×40 and the turned box overflows it. Fix: run the filled size through
   `applyRotationExpansion` as `measurement(of:measured:)` does, keeping the raw size as
   `measuredWidth/Height` (the rect's `unturnedSize`).
2. **Bug — a turned child with `fill_container` on the cross axis (f20).** Pen fills the
   child's *unturned* height with the row's inner height (100), then lays out the turned
   bounds (100×60). Woodcase writes a 100×100 rect — the stretched cross size unexpanded —
   and draws the box 20 pt low. Same fix, on the cross-fill path.
3. **Pen artifact — first layout after load (f20, f21).** Pen sizes widths before heights
   (`VBe`: `cie(t,0),uie(t,0),cie(t,1),uie(t,1),qBe(t)`), so a turned child whose height is
   not resolved yet (a `fit_content` frame, a cross-axis fill) is measured with height 0
   when its parent's width is fitted. Any later relayout converges on Woodcase's numbers,
   so Pen is not idempotent here, and `pen-oracle` exports and `layout.json` capture the
   first pass. Recommendation: keep Woodcase's converged answer ("better than Pen") and
   document it; a fixture for this case must not use Pen's first-pass `layout.json` as its
   expectation.

   > **Corrected 2026-09-28 (leaf `YrLTHN`):** wider than f20/f21. The first pass also
   > misplaces a turned main-axis fill in a *column* (80 wide on load vs 161.96 settled, and
   > 80 vs 200) and cross-axis fills in `fit_content` rows (160 vs 200, 211.96 vs 231.96), and
   > some cases need two relayouts to settle. `scripts/pen-settle` writes both layouts;
   > PenInteroperability.md's "Kept Divergences" lists the figures (`flex-turned-fill.pen`).
4. **Framing — `shot` frames the layout rect; Pen's export frames the painted extent.**
   Not a paint bug, but it is why a raw `png-mae` of a stroked or shadowed root is
   meaningless and why render fixtures carry hand-measured overflow offsets (gotcha
   2026-08-29). Fix follows from the model: a library painted-extent function, which
   render tests use to place Pen's reference, and an opt-in `shot --extent painted`.
5. **Penumbra hit-testing** (code read, not probed): `HitTestEngine` tests the axis-aligned
   absolute rect, so a turned node is hit in the empty corners of its bounds and missed on
   its outer stroke band. Pen hits the turned box, else the stroke band.
6. **Painted extent computed privately.** RapidPro's `RenderNode.paintedBounds` (culling)
   is its own computation; Woodcase has none; Penumbra has none. Pen's rule is one
   function.

## Proposed model

Three named extents, each with one owner and one set of readers.

**(i) Bounds — the layout rect.** The axis-aligned bounds of the node's turned, flipped
box, in its parent's coordinates. It is what a parent allocates and aligns, what a group
unions, what Pen's layout reports, and what `PenRect`'s `x`/`y`/`width`/`height` already
are. Readers: the layout engine, `tree` rows (`rect`, `absRect`), `shot --outline` and
`shot --crop` coordinates, overlap and root-overlap lint, snapping and marquee selection in
Penumbra, codegen's positioned wrappers.

**(ii) Box + transform — the drawn geometry.** The box `0,0,w,h` (a group's: its
children's union, measured from its anchor) and the affine map into the parent: Pen's
translate-to-anchor · turn · flip. Woodcase spells it as the box centered in the bounds,
flipped and turned about its center — the same quad, because a turned rectangle's bounds
are centered on its center — and exposes it as `unturnedBox(of:rect:layoutRects:)` plus
`canvasTransform(of:in:layoutRects:)`. Readers: every renderer (CG, RapidPro, React,
SwiftUI), the space children's rects are measured in, and hit-testing (point in the
turned quad), selection handles and drag in Penumbra.

**(iii) Painted extent — what may carry ink.** Box ∪ stroke band (alignment, per side,
mitered corners) ∪ unclipped children's painted extents through their transforms, then
each outer shadow's offset copy ± 1.5·blur and a layer blur ± 1.5·radius, all through the
node's transform — Pen's `getVisualLocalBounds`, reproduced, including its choice to leave
spread out. Never an input to layout. Readers: export and `render` canvas size, `shot
--extent painted`, render-test placement of Pen's references, viewport culling (RapidPro,
Penumbra tiles), dirty-rect invalidation, and stroke-band hit-testing.

### Does `PenRect` express it?

Yes, for (i) and (ii), and it should stay bounds-first. The alternative — `PenRect` as
anchor + unturned size + turn/flip, with bounds derived — mirrors Pen's storage, but every
layout-facing reader (the flex engine itself, tree, lint, outline, marquee, codegen) wants
the bounds, and a group's box does not start at its anchor, so "anchor + size" still needs
a union beside it. The turn and flip are already on the node; `unturnedSize` is the one
number the node cannot supply, and the rect carries it. What is missing is naming, not
shape:

- a `PenPlacement` value (box + `PlaneTransform`) returned by one function, so a reader
  asks for (ii) by name instead of composing `unturnedBox` and a transform by hand;
- a `paintedExtent(of:rect:layoutRects:)` for (iii), in the library, which RapidPro's
  `paintedBounds`, Penumbra and `shot` all read;
- `PenRect`'s doc comment states it is extent (i) and points at the other two.

### Recommendation and cost

**Keep `PenRect` as it is; add (ii) and (iii) as named library API; fix divergences 1
and 2; rule on 3 as "keep the converged layout".** Cost:

- Woodcase: additive API (a struct, two functions, docs in PenEngine.md / PenRendering.md),
  the two flex fixes with red/green tests on a focused fixture (f16, f20 and a free/flex
  pair per case, with a hand-checked expectation for f20/f21 rather than Pen's first
  pass), `shot --extent painted`, and render-test helpers that place Pen's reference by
  the painted extent. No breaking change; the flex fixes change rects only for turned
  `fill_container` children.
- RapidPro: replace its private painted-bounds computation with the library's (one
  producer call site); verify culling unchanged on its suite.
- Penumbra: hit-test the turned quad and the stroke band (via (ii) and (iii)) instead of
  the absolute bounds — a behavioral change to selection, which its hit-test tests pin.

The bounds-first reshape to box + transform would instead touch every `PenRect` reader
across the three repos (layout engine, tree, lint, viewer, codegen, `RenderNodeProducer`,
Penumbra's absolute rects, hit test and drag) for no behavioral gain.

## What the brief assumed

- "Strokes never enter Pen's layout" was right, turned nodes included, and even with
  `layoutIncludeStroke: true`.
- `pen-oracle`'s `layout.json` is Pen's *first* layout after load, not always its settled
  one (divergence 3).
- `png-mae` resamples images of different sizes silently, so a Pen export framed on the
  painted extent against a `shot` framed on the layout rect ranks framing, not paint.
- The 2.17 schema notes in `local/Pen-Schema-2.17.md` still say rotation "pivots at the
  node's center in the render"; Pen's matrix pivots at the anchor. Woodcase's center pivot
  inside the bounds draws the same quad, so it is an equivalent spelling, not the rule.
