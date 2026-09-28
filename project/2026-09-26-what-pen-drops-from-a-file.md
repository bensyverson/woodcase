# 2026-09-26 — What Pen drops from a file: text styles and malformed meshes

Evidence behind three lint checks — `text-style-stripped`, `mesh-gradient-dropped` and
`mesh-gradient-distorted` — and a recommendation on how Woodcase should decode a
malformed mesh point. Leaves `rjt7to` and `JXbZb2`. Every claim below is Pen's
observable output: what it reports after loading a file, what it saves, and what its
export draws. Probe files lived in a gitignored `local/` scratch directory and are
described inline, not committed.

## Text: stroke, underline and strikethrough

**Confirmed in Pen.app 1.2.14**, and in the headless `pen` CLI engine: Pen strips all
three from a `text` node when it opens a file, and draws none of them. This settles
finding 4 of [the text-and-stroke-fills report](2026-09-26-text-and-stroke-fills.md),
which had observed it in the CLI engine only.

The probe was one 400×300 frame (`layout: none`) holding four Inter 40 pt text nodes:
a control; one with `fill: #FFFFFF`, `stroke: #FF0000`, `strokeWidth: 4`,
`strokeAlignment: outer`; one with `underline: true`; one with `strikethrough: true`.

```
open -a Pen probe-app.pen                                       # sandbox off
pen interactive --app desktop --in probe-app.pen < app.txt      # sandbox off
#   app.txt: get_app_state(); execute Get(n => print every text node as JSON);
#            execute Export(['board'], 'png', <dir>, {scale: 1}); save(); exit()
pen interactive --in probe.pen --out headless-saved.pen < headless.txt   # the CLI engine
```

- The nodes Pen.app reports after load carry no `stroke`, `strokeWidth`,
  `strokeAlignment`, `underline` or `strikethrough` key.
- Its export draws the control, *nothing visible* where the white stroked text sits
  (no red outline), and the other two as plain text.
- `save()` writes format `2.19`; none of the five keys survives. The CLI engine's save
  is the same.

So Woodcase lints each case (`text-style-stripped`, a warning). Per decision 2 of the
report, Woodcase keeps drawing underline and strikethrough; it draws no text stroke.

## Mesh gradients

Headless `pen` CLI, one probe file of 100×100 frames, each with one mesh fill. After
load (`Get`), after `save()`, and in a 1× export:

| Probe | What Pen kept | What it drew |
|---|---|---|
| 2×2, four 6-digit colours | kept | the four-colour mesh |
| colours as `#F00F` (4-digit `#RGBA`) | kept verbatim | nothing (transparent) |
| colours as `#F00` (3-digit) | kept | identical to the 6-digit control |
| 3 points on a 2×2 grid | **the whole fill removed** | nothing |
| 3 colours on a 2×2 grid | **the whole fill removed** | nothing |
| `rows: 1` (2 points, 2 colours) | kept | nothing |
| one point written `[1]` | kept, as `[1, null]` | nothing |
| one point written `"oops"` | replaced by its default grid position | like the control |
| the mesh report's folded `mfold` | kept | the folded, partly bare shape |

`mesh-gradient-dropped` (error) reports the count mismatches, a missing `columns`,
`rows`, `points` or `colors` (inferred from the same removal, not probed separately),
and a grid under 2×2. `mesh-gradient-distorted` (warning) reports `#RGBA` colours and
folds.

### What counts as a fold

A patch folds where its Bézier surface turns over — where the Jacobian of
`(u, v) → position` goes negative. `MeshFoldDetector` samples it at 33 × 33 parameters
per patch and reports a patch whose most negative sample is deeper than 5% of the
patch's mean. The threshold is empirical. A scratch Python port of the same test over
the report's Appendix A meshes gave:

| Mesh, patch | Most negative sample | Mean | Share of samples negative |
|---|---|---|---|
| `mfold` (0,0) | −1.28 | 0.62 | 43% |
| centre vertex of a 3×3 dragged to x = 1.3, patches (1,0) and (1,1) | −0.27 | 0.054 | 34% |
| `mwarp` (0,1) | −0.0008 | 0.13 | 0.3% |
| every other patch of `mwarp`, `mcurve`, `m4x3` | ≥ +0.029 | — | 0% |

`mwarp` is strictly folded in a sliver, but Pen's export of it matched the port at MAE
0.000 and shows nothing; the threshold sits two orders of magnitude above it and more
than an order below the real folds. Not detected: a fold narrower than one sample step,
and two patches overlapping without either turning over.

## Recommendation: a malformed mesh point should not fail the file

Since `4df55f2`, a mesh point that is neither `[x, y]` nor an object with a `position`
fails decoding, and with it the whole document — so every Woodcase verb, `lint`
included, refuses a file Pen opens. Pen never refuses it: it repairs a non-array point
to its grid position, keeps a short array and draws nothing for that one fill.

Recommended: decode a malformed point as a preserved raw value — a `PenMeshPoint` case
carrying the JSON as written, round-tripped verbatim, per the "preserve only" ruling
for unknown content — let the renderer treat it as Pen does, and have
`mesh-gradient-dropped` report it. Not done in `JXbZb2`: it adds a case to the public
`PenMeshPoint` enum and makes `position` partial, which the mesh tessellator leaf
(`OHdROl`, in flight) consumes. It wants the same coordination as the `.unknown` cases
`CIcquU` adds to `PenFill` and `PenEffect`.

> **Built in `DIkwEJ` (2026-09-26), with two refinements from wider probes below.**
> "A non-array point is repaired, a short array draws nothing" was the right shape but
> too coarse: what decides is whether Pen's arithmetic can read the value, not whether
> it is an array. And only an unplaceable point is `mesh-gradient-dropped`; a point Pen
> places anyway paints the mesh, so it is `mesh-gradient-distorted` (a warning).

## Malformed points, measured

Leaf `DIkwEJ`. Headless `pen` CLI 0.3.9, sandbox off. Two scratch probes of 3×2 meshes,
each with vertex 2 (or 5) malformed, then the committed fixture
`Tests/WoodcaseTests/Fixtures/render-mesh-malformed-points.pen`:

```
scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-mesh-malformed-points.pen --scale 1,2 --accept-invalid
```

(`--accept-invalid` is new: Pen prints `[ERROR] Document is not valid:` for these files
and then loads, draws and saves them anyway.) "Draws" compares Pen's 1× export against a
control with the vertex written as Pen re-saved it; every "as saved" row matched at MAE
0.000, every "nothing" row is fully transparent.

| Vertex written | Pen's re-save | Draws |
|---|---|---|
| `"oops"`, `null`, `42`, `true` | the grid position, e.g. `[0.5, 0]` | as saved |
| `{}`, `{"position": null}` | the grid position | as saved |
| `{"leftHandle": [-0.3, 0.2]}` | `{"position": [0.5, 0], "leftHandle": [-0.3, 0.2]}` | as saved |
| `[0.3, 0.2, 9]`, `[0.3, 0.2, "x"]`, `{"position": [0.3, 0.2, 5]}` | `[0.3, 0.2]` | as saved |
| `{"position": [0.3, 0.2], "leftHandle": [-0.3, 0.2, 5]}` | the handle truncated | as saved |
| `{"position": [0.3, 0.2], "leftHandle": null}` | `[0.3, 0.2]` | as saved |
| `[0.3, null]` | `[0.3, 0]` | as saved |
| `[true, false]` | `[1, 0]` | as saved |
| `[1]`, `[]` | `[1, null]`, `[null, null]` | nothing, whole fill |
| `["a", "b"]`, `[0.3, "x"]` | `null` for each string | nothing, whole fill |
| `["0.3", "0.2"]`, `[[0.3], [0.2]]` | `[0.3, 0.2]` | **nothing**, whole fill |
| `{"position": "oops"}`, `{"position": [1]}` | `[null, null]`, `[1, null]` | nothing, whole fill |
| handle `[1]`, `"oops"` or `{}` | the handle with `null`s | nothing, whole fill |

The rule that fits every row is JavaScript's: a point that is not an array reads its
`position` and handles with `??` (absent or `null` takes the default, and a string or
number has no `position`); an array is indexed `[0]`, `[1]`; and each entry goes
through arithmetic, where a number is itself, `null` is 0, a boolean 0 or 1, and
anything else is `NaN` — which poisons the whole fill. The save's rounding goes through
`Number()` instead, which is why `["0.3", "0.2"]` saves as numbers yet draws nothing.
`PenMeshPoint.placement(gridPosition:defaults:)` implements the rule; the fixture pins
the renderer to Pen's exports (`PenMeshMalformedPointSnapshotTests`).
