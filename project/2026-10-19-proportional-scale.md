# Proportional scale (leaf LyBgNr)

Penumbra's Scale mode (Penumbra leaf 2CE2C0, interaction spec §5, Ben's rulings of
2026-10-14 session 21 and 2026-10-18 session 31) needs one library operation that scales a
selection by one factor about an anchor and returns the edits, so the CLI and agents get the
same behavior. This note records the API and the calls left to the builder. Every call
below is a two-way door; revisit freely.

## The API

- `ScaleCapture(nodeIDs:in:layout:)` captures the selection at gesture start: the
  top-most members, their canvas union (`bounds`), and every node they draw (refs
  expanded, overrides applied, variables kept), each with where its edits are stored and how it
  moves. `plan(factor:around:in:)` (a canvas point) and `plan(factor:anchor:in:)` (one of
  the nine `ScaleAnchor` points of `bounds`) turn the capture into a `ScalePlan`. Each plan
  starts from the capture, so a live drag that plans 1.2, 1.5, then 2 gets exactly what
  planning 2 once gets. Factors never compound.
- `ScalePlan.operations` are property edits only (`setProperties`, `overrideDescendant`,
  `overrideRoot`), each planned through `EditPlanner`. They preview with
  `EditableDocument.previewNodes(for:)` and commit as one `LocalEdit`, which is one undo
  step. `ScalePlan.unscaled` lists each value a variable supplies.
- `EditPlanner.planScale(nodeIDs:by:anchor:in:layout:)` captures and plans in one call,
  for the inspector's Scale % field and `woodcase scale`.

## What scales

The session 21 list: position relative to the anchor, width and height (and a
`fit_content(n)`/`fill_container(n)` fallback), font size, letter spacing, stroke widths
(uniform and per side), corner radii, effects (shadow offset and blur, layer blur and background
blur), gap and padding. It descends into children. A member placed by its own `x`/`y` is
moved so its every point lands where the scale about the anchor sends it on the canvas, under a
turned or flipped parent too. The tests compare canvas quads. A member its stack places
only grows in its slot.

Things the brief did not spell out:

- **Line height is never scaled.** In this format `lineHeight` is always a multiple of the
  font size (the planner refuses one written in points), so "absolute line height" has no
  case to cover. The brief's "line height when absolute" is moot for `.pen`.
- **Path geometry is not rewritten.** A path's geometry is drawn into its box (through its
  `viewBox`, or its tight bounds when it has none), so scaling `width` and `height` scales the
  points.
- **Unset values are scaled as drawn.** A text with no `fontSize` draws at 16 pt, so it is
  written at 16 × the factor; a stroked node with no `strokeWidth` draws at 1. A note with
  no size draws at 200 × 200.
- **Rich-text runs** (`metadata.woodcase.spans`) scale their own `fontSize`; the text and offsets
  are kept, so the spans stay fresh.
- **Shadow spread** (`metadata.woodcase.shadowSpread`) scales its `spread` *and* the
  shadow snapshot it was made for, exactly as the node's shadow scales. Without that the
  entry would turn stale and the shadow would lose its spread.
- **Text sizing modes are never written.** `auto` keeps fitting its words, `fixed-width` keeps its
  height following them, `fill_container` keeps filling.

## The calls (two-way doors)

1. **Notes, prompts and contexts scale as a whole**: their box and their text style (the
   type size in `metadata.woodcase.fontSize`, and letter spacing when set). Scale's one
   promise is "everything, by one factor", and a note's own resize already scales its type
   with its box (spec §5.9). Only-move would make a note the one thing Scale does not scale.
   The resize ruling of 2026-10-12 (a note in a multi-selection resize keeps its type size)
   is about resize, which is geometry-only by the session 21 ruling.
2. **Variable-bound values stay bound** and are reported in `ScalePlan.unscaled` (node,
   property, variable). Scaling one would either unbind it or change the variable for every
   node that reads it.
3. **Dash patterns scale with the stroke**: `metadata.woodcase.strokeDash` lengths and
   `strokeDashOffset` are multiplied, so a scaled dashed border looks the same, only
   bigger. The miter limit is a ratio and stays.
4. **Rounding: scaled lengths keep fractions to a hundredth of a point** (the precision
   nudge keeps, spec §4.5), and a length above zero never rounds to zero. Whole points would
   break proportion at small factors (a 1 pt stroke at 0.5 is 0.5, not 0 or 1), and
   unrounded values would write float noise such as 13.333333333333334. The live gesture plans
   each step from the start, so rounding never accumulates. Figma's scale tool also keeps fractional results;
   I did not check Sketch.
5. **A factor of 1 writes nothing**, and a factor that is not positive and finite is
   refused (`outOfRange`, property `factor`).
6. **An instance root splits its writes** as Penumbra's `TransformWrites` does: `x`/`y`
   are the `ref` node's own; everything else is a root override. Nodes inside an instance
   are overrides on the outermost instance. The component never changes.

## CLI

`woodcase scale <file> <nodes…> --by <factor|percent> [--anchor top-left|…|bottom-right]`,
one transaction (one `woodcase undo`), `--json` reporting `{operations, unscaled, revision}`.
The default anchor is `top-left`, the corner whose `x`/`y` a node is written at.

## Cost

Capture walks the expanded subtrees once and reads every scalable value then, so a step
is arithmetic on captured values plus one write per node that changes: a plain
`setProperties` on a node with storage of its own (no planner pass, since every value is
one the node held times a positive factor), and an `EditPlanner` override inside an
instance.

Measured 2026-10-19 with a throwaway Swift Testing probe (`swift test --filter
LyBgNrScaleCostProbe`, debug build, machine load 60–80, probe deleted afterwards). The
selection was 30 stacks of three children each plus 10 instances of a two-node component:
140 captured nodes and 150 edits a step. Capture took 16–27 ms once. A step took 8.6 ms to
plan and 17.5 ms to plan and run `previewNodes(for:)`. Computing the values took 0.3 ms
of that; the rest is building the writes (own nodes about 6 ms, the 20 instance writes about
2 ms). The first version planned every own-node write through `EditPlanner` and read values
through the codec on each step, and took 107–128 ms a step. A release build will be faster;
not measured.
