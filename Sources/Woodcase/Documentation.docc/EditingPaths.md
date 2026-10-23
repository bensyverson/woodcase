# Writing and Editing Paths

Turn a `path` node's geometry into anchors a pen tool can edit, and anchors back into the
`geometry`, box and `viewBox` the node writes — exactly, so committing every anchor never
moves one.

## Overview

A `path` node stores SVG path data (`geometry`), a box (`x`, `y`, `width`, `height`) and
optionally a `viewBox` that maps the geometry onto the box. Three layers sit between that
and an editor:

1. ``PenPath`` is the parsed geometry (``PenPath/init(svg:)``), and
   ``PenPath/svgPathData`` writes it back out.
2. ``PenPathContour`` and ``PenPathAnchor`` are the same path as anchors with in and out
   handles: ``PenPath/contours`` and ``PenPath/init(contours:)`` convert.
3. ``PenPathFrame`` places anchors drawn in the parent's space: the box, viewBox and
   node-local geometry to write, and the anchors read back from a node.

Each layer is exact where the one above it relies on it: none of the conversions does
arithmetic on a coordinate it does not have to, and the one that must (moving geometry
into node-local coordinates) keeps every value on a hundredth-of-a-point grid so that
repeating it changes nothing.

## Writing path data

``PenPath/svgPathData`` writes every command absolute — `M`, `L`, `Q`, `C`, `Z` — because a
``PenPath`` holds only resolved commands: relative commands, `H` and `V`, the reflected
control points of `S` and `T`, and elliptical arcs were all resolved when it was parsed.
Each number is the shortest text that reads back as the same `Double` (whole numbers
bare, `1e-07` where an exponent is shorter), so for every path the parser produces,
`PenPath(svg: path.svgPathData) == path`. `PenPathFixtureRoundTripTests` checks that over
every `geometry` in the test fixtures. ``PenPath/svgPathData(number:)`` takes a formatter
for an emitter that wants a fixed precision instead; only the exact form round-trips.

The shape outlines' SVG writer (`PenShapeOutline.svgPathData(number:)`, used by the React
emitter for arcs and rings) is the same writer with the outline's extra primitives on top.

## Anchors and handles

A ``PenPathAnchor`` is a point with an in handle and an out handle, all absolute positions
in the same space. A handle exactly on its point is retracted. Between two anchors a
contour draws a line when both facing handles are retracted, otherwise a cubic Bézier
whose control points are the first anchor's out handle and the second's in handle. A
closed ``PenPathContour`` also draws a segment from its last anchor back to its first;
when that segment is straight the `Z` draws it.

Because handles are positions rather than offsets, both directions of the conversion copy
coordinates: `PenPath(contours: c).contours == c` for any contours, and through the
geometry text too, any number of times. The one exception is by design: an *open*
contour's first in handle and last out handle face no segment, so geometry cannot carry
them, and they come back retracted. A pen tool that shows the trailing handle of a path
still being drawn keeps it itself.

Reading geometry as anchors:

- A cubic's control points become the handles either side of it.
- A **quadratic** becomes the cubic that draws the same curve, its handles two thirds of
  the way from each end to the control point. Its anchors write back as a `C`, not a `Q`.
- An **elliptical arc** was converted to cubics of at most 90° when parsed, so its anchors
  are those cubics' ends, smooth where they join; editing an arc edits those cubics. The
  last cubic of an arc ends exactly on the arc's end point.
- On a close, a final segment that ends exactly on the subpath's start is the first anchor
  arriving again: its in handle becomes the first anchor's and no anchor is added. Writing
  keeps that unambiguous: a closed contour whose last anchor sits on its first writes the
  closing segment explicitly, so both anchors come back.
- Several subpaths are several contours. Drawing on after a `Z` without a move starts a
  new contour at the closed one's start; data that starts without a move starts at the origin.

### Corner, smooth, mirrored and broken

A `.pen` file stores only geometry, so how an anchor's handles relate is read from their
positions — ``PenPathAnchor/kind`` — and tells an editor what dragging one handle does to
the other:

| ``PenPathAnchor/Kind-swift.enum`` | Handles | Dragging one handle |
|---|---|---|
| `corner` | neither extended | — |
| `smooth` | opposite, different lengths | turns the other to stay opposite |
| `mirrored` | opposite, same length | moves the other to its reflection |
| `broken` | not opposite, or only one extended | leaves the other alone |

``PenPathAnchor/KindTolerance/standard`` is the named tolerance: handles within 0.01 rad
(about half a degree) of opposite are smooth, lengths within 1% of each other are
mirrored, and a handle under a millionth of a point long has no direction and counts as
retracted for classification (geometry still draws it as a curve). Pass a looser
tolerance with ``PenPathAnchor/kind(tolerance:)``. A pen-tool drag pulls mirrored handles:
``PenPathAnchor/init(point:mirroringOutHandle:)``.

### Adding an anchor on a segment

Segments are numbered from their start anchor: segment `i` joins anchor `i` to anchor
`i + 1`, and a closed contour's last segment, `anchors.count - 1`, is the closing one back
to anchor 0. ``PenPathContour/nearestPoint(to:)`` finds where a pointer is nearest the
drawn path — exactly by projection on a straight segment, by sampling and Newton's method
on a cubic (good to about 10⁻⁶ of a point) — as a ``PenPathContour/NearestPoint``: the
segment, the curve parameter `t`, the point and its distance.
``PenPathContour/insertingAnchor(inSegment:at:)`` then splits that segment there without
changing the drawn shape: on a cubic by de Casteljau's construction, shortening the
neighbors' facing handles and giving the new anchor smooth handles; on a straight
segment, a corner at the straight-line point.

```swift
if let hit = contour.nearestPoint(to: pointer), hit.distance <= hitRadius {
    let (split, index) = contour.insertingAnchor(inSegment: hit.segment, at: hit.t)
    // `split.anchors[index]` is the new anchor.
}
```

## Placing a path node

``PenPathFrame/init(contours:precision:)`` takes anchors in the node's parent space and
returns what the node writes:

- **The box** is the path's drawn extent — ``PenPath/tightBounds``, where control points
  count only where the curve reaches — widened outward to the next hundredth of a point.
- **The geometry** is the path moved so the box's corner is its origin, each coordinate
  kept to a hundredth.
- **The viewBox** is `[0, 0, width, height]` when the box has both a width and a height, so
  the geometry maps onto the box one to one and no reader has to recompute its bounds.

A straight horizontal or vertical path has no extent across itself, and a viewBox with a
zero side cannot be mapped (``PenViewBox/isUsable``), so such a path writes **no viewBox**.
Without one, Pen maps the geometry's drawn extent onto the box, translating an axis with
no extent rather than scaling it; Woodcase does the same (``PenPath/mapped(onto:viewBox:)``),
and both draw a horizontal path of height 0 on its box's top edge, ignoring the
geometry's own offset (checked with the `pen` CLI's headless renderer against
`woodcase render`, MAE 0.0, 2026-10-23). So for such a path the frame sets the box to
exactly the geometry's drawn extent — not rounded — and the mapping is a pure translation.
A horizontal path from (10, 20) to (110, 20) writes `x` 10, `y` 20, `width` 100,
`height` 0, no viewBox, and `geometry` `M0 0 L100 0`.

``PenPathFrame/contours(precision:)`` reads anchors back in the parent's space, mapping the
geometry onto the box as Pen draws it — through a viewBox that need not match the box, or
through the geometry's extent when there is none — and keeping each coordinate to the
same grid. So anchors on the grid read back unchanged, and writing what was read gives
the same node properties every time: no drift however many anchors the tool commits. A
node whose box was stretched away from its viewBox reads back stretched, and the next
write folds the stretch into the geometry.

The frame works in the parent's space before the node's rotation and flip; an editor
working on a turned node maps its points through the node's transform on the way in and out.

```swift
// Anchors the pen tool placed, in the parent's space.
let contour = PenPathContour(anchors: [
    PenPathAnchor(point: PenPoint(x: 40, y: 80)),
    PenPathAnchor(point: PenPoint(x: 120, y: 40), mirroringOutHandle: PenPoint(x: 160, y: 40)),
    PenPathAnchor(point: PenPoint(x: 200, y: 80)),
], isClosed: false)
guard let frame = PenPathFrame(contours: [contour]) else { return }
// Write frame.x, frame.y, frame.width, frame.height, frame.viewBox and frame.geometry.

// Later, from the node's laid-out box:
let anchors = PenPathFrame(x: x, y: y, width: w, height: h, viewBox: viewBox, geometry: geometry)?
    .contours()
```

## Topics

### Geometry

- ``PenPath``
- ``PenPathCommand``

### Anchors

- ``PenPathContour``
- ``PenPathContour/NearestPoint``
- ``PenPathAnchor``

### Placing a node

- ``PenPathFrame``
- ``PenViewBox``
