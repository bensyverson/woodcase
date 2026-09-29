# Absolute containers, `fit_content`, and the group anchor

2026-08-29 · issue leaf `AkYRr`

> **Correction, 2026-09-27 (leaf `Jg0BOv`):** the union rule below is wrong for a
> **frame**. It was inferred, never measured against Pen; Pen settles a `layout: "none"`
> frame's `fit_content` axis at its fallback — 0 by default — never around its children,
> and re-saves a missing size as `fit_content(0)` (probe `render-sizeless-frames.pen`,
> `PenSizelessFrameTests`). The old `contentSize: 0` was right for frames and wrong only
> for groups. Groups keep a union (the true one, not one from the anchor — leaf `cqBw2i`).

## What was wrong

`PenLayoutEngine.layoutAbsoluteContainer` passed `contentSize: 0` to
`resolveContainerSize` for both axes, so a `fit_content` container with
`layout: "none"` — a frame, and *every* `group`, since 2.17 leaves a group no
declared size — reported `(0, 0)` no matter what it contained. The 2.17 model
says a group's bounds are the union of its absolutely positioned children
(commit `222c3a6`), so this was a correctness gap; `222c3a6` recorded it and
left it for this task.

## The union, precisely

For a container that places its children absolutely, a `fit_content` axis now
resolves to the extent of its children measured **from the container's own
origin**:

```
contentWidth  = max(0, max over enabled children of (child.x + childRect.width))
contentHeight = max(0, max over enabled children of (child.y + childRect.height))
```

`childRect` is the rect the engine writes for the child — its size after its own
layout, expanded to the rotated bounding box when it is rotated. So:

- **Negative offsets overhang, they do not grow the box.** The container's origin
  is pinned by its own `x`/`y`; only the right and bottom edges move. A child at
  `x: -10` hangs outside the box and is drawn there unless the frame clips.
- **A rotated child contributes its rotated bounding box.** That expanded box
  *is* the child's layout rect, and it is exactly what a flex parent already
  counts for the same child (`layoutFlexContainer` calls
  `applyRotationExpansion` before summing). Making the absolute path use the
  un-rotated declared box instead would let the union fail to contain the rects
  the engine itself wrote. Flip is area-preserving and changes nothing.

  > **Correction, 2026-09-27 (`nAuBKh`):** that box is no longer anchored at the child's
  > `x`/`y`. A turned or flipped child's rect sits where turning and flipping about its
  > anchor puts it, so the union counts that rect's right and bottom edges
  > (`rect.x + rect.width`), which is what the code always summed. "Flip changes nothing"
  > was wrong: Pen mirrors a flipped node about its anchor, so a `flipX` child's rect moves
  > its width to the left.
- **Disabled children are excluded**, matching the flex path.
- **`padding` is not reserved** — an absolute container does not offset its
  children by padding, so it does not reserve room for it.
- **Only `fit_content` changes.** `fixed(n)` and `fill_container` are untouched,
  and `fit_content(fallback)` still falls back when the union is zero.

## The finding: a group is an anchor, not a box

Giving a group a real size moves the render, because `PenTransformBuilder`
pivots rotation at the center of the node's rect. That would have broken the
`blur2`/`blur2-no-bg` snapshots, which sit at MAE `7.658` and **`0.000`** — a
pixel-perfect match with Pen's own PNG. So Pen's group cannot be a box the
rotation pivots through the middle of.

`blur2.pen`'s group is the proof. It stores `x: -111.42492757477771`,
`y: 100.00000000000004`, `rotation: -315`, and its two children form a 299×299
square. Those coordinates are exactly where the group's **local origin** lands
when a 299×299 group at `(-49.5, -49.5)` — centered in the 200×200 frame — is
swung 45° about its own center:

```
$ python3 - <<'EOF'
import math
ROT, UNION = -315.0, 299.0
origin = (-49.5, -49.5)
center = (origin[0] + UNION / 2, origin[1] + UNION / 2)
rad = -ROT * math.pi / 180              # the renderer's screen rotation
c, s = math.cos(rad), math.sin(rad)
v = (origin[0] - center[0], origin[1] - center[1])
print(center[0] + v[0]*c - v[1]*s, center[1] + v[0]*s + v[1]*c)
EOF
-111.42492757477771 100.00000000000006
```

That agrees with the stored `x`/`y` to `1.4e-14` — Pen's own float noise (the
same noise appears in the fixture's child `y: 1.2434497875801753e-14`).

So: **when a user rotates a group, Pen pivots at the center of the group's
bounds and then bakes the result into the group's `x`/`y`, rewriting it to where
the group's local origin landed.** The persisted `x`/`y` is the anchor of the
children's coordinate system, not the corner of a bounding box. At render time
the rotation replays about that anchor. The rival model — `x`/`y` as the union's
top-left with a center pivot — puts the diamond's center at `(38.08, 249.50)`
instead of `(100, 100)`, i.e. almost entirely outside the 200×200 artboard;
`blur2-no-bg.png` shows a full-bleed diagonal split, so it is centered.

Two consequences, both implemented:

- `applyRotationExpansion` exempts a `group`. Its rect is the **un-rotated**
  union, because its `x`/`y` is not the corner of a bounding box to anchor.
- `PenTransformBuilder.buildTransform` pivots a `group` at `(0, 0)` of its rect
  rather than the center.

Together these keep the rendered output bit-identical while the group's rect
becomes its true bounds. Every MAE in `PenSnapshotTests` is unchanged to the
digit — see below.

## Why the schema comment is not the answer either

`Entity.rotation` in `local/Pen-Schema-2.17.md` reads *"Degrees CCW around
top-left corner."* `project/gotchas.md` already records that this describes the
*position anchor*, not the render pivot, for sized nodes: pivoting a rectangle
at `(0,0)` moves `render-transforms-and-effects` from MAE 1.12 to 10.77. Both
readings are true at once, of different node kinds — a sized node's declared
`x`/`y` is the top-left of its **rotated bounding box** and its pivot is the
box's center; a group's declared `x`/`y` is a **point**, and the pivot is that
point. The prose is not a rule you can apply uniformly.

> **Correction, 2026-09-27 (leaf `nAuBKh`, F4 of `2026-09-27-fidelity-gaps.md`): the
> sized-node half of this paragraph was wrong.** A sized node placed by its own `x`/`y`
> is *not* the top-left of its rotated bounding box. Pen turns (and flips) it about its
> `x`/`y` — the schema's literal reading — and its settled layout reports the bounds of
> the result, which reach left of or above the anchor: `render-rotated-free.pen`'s
> 200×60 rectangle at `(80, 60)`, turned −20°, settles at `(59.479, 60)`, and a
> `flipX` node settles its whole width left of its anchor (`render-transformed-free.pen`,
> both Pen-oracle fixtures). The center pivot that scored 1.12 on
> `render-transforms-and-effects` was right only because that fixture's turned node is a
> **flex child**, whose slot Pen grows to the turned bounds. The center pivot is still what
> the renderer uses, now inside bounds the layout has moved to where the anchor turn puts
> them, which draws the same picture. The group half stands.

## Numbers

Baseline and post-change, `swift test --filter "PenSnapshotTests"` (worktree,
sandbox disabled). Nothing moved:

| Snapshot | Before | After | Threshold |
|---|---|---|---|
| `blur1` | 1.4115625 | 1.4115625 | 5.0 |
| `blur2` | 7.65750625 | 7.65750625 | 15.0 |
| `blur3` | 16.5103625 | 16.5103625 | 25.0 |
| `blur2-no-bg` | 0.0 | 0.0 | 5.0 |
| `blur3-no-bg` | 0.09728125 | 0.09728125 | 5.0 |
| `render-transforms-and-effects` | 1.1222287132289934 | 1.1222287132289934 | 8.0 |
| `render-shapes-and-fills` | 0.015783595882620564 | 0.015783595882620564 | 5.0 |
| `render-gradients` | 0.66882131649192 | 0.66882131649192 | 5.0 |
| `gradient-extras` | 0.048634375 | 0.048634375 | 5.0 |
| `render-strokes-and-paths` | 5.113791082974138 | 5.113791082974138 | 8.0 |
| `render-clipping-and-gradients` | 0.6215724158653846 | 0.6215724158653846 | 5.0 |

`swift test --quiet`: 1692 tests in 159 suites, all passing. No threshold was
touched and no reference PNG was regenerated.

`blur3`/`blur3-no-bg` were predicted to move and did not: their groups carry no
rotation, and a group draws no content of its own, so its rect only reaches the
render through the transform pivot and the shape path for effects — neither of
which those groups use.

## Still open

- The absolute-children branch of `layoutFlexContainer` (children with
  `layoutPosition: .absolute`) writes their rects **without**
  `applyRotationExpansion`, unlike every other placement path. Out of scope
  here; worth a leaf of its own.
- No Pen render exercises a `fit_content` frame with `layout: "none"` — the
  union rule for that case is inferred from the group's, not measured.
  `Tests/WoodcaseTests/Fixtures/layout-absolute-fit-content.pen` asserts
  geometry only, deliberately, and is not in `PenLayoutEngineTests`'
  ground-truth fixture list.
