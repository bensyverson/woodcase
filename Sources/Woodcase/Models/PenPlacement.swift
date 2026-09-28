//
//  PenPlacement.swift
//  Woodcase
//

import Foundation

/// Where a node is drawn: its box in its own coordinates, and the map that carries that
/// box into another space — extent (ii) of the three the library names.
///
/// Every node has three extents (`project/2026-09-28-geometry-model.md`):
///
/// - **(i) Bounds** — ``PenRect``: the axis-aligned bounds of the node's turned, flipped
///   box in its parent's coordinates. What layout allocates and aligns, and what `tree`
///   reports.
/// - **(ii) Placement** — this value: the box `0, 0, w, h` (a group's is its children's
///   union, measured from its anchor, so it may start anywhere) and the affine map that
///   turns, flips and moves it into its parent's coordinates, or the canvas's. The map
///   sends the box to the quad the node is drawn as, and that quad's bounds are (i). What
///   a renderer draws with, and what a hit test or a selection handle wants.
/// - **(iii) Painted extent** — ``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)``:
///   what may carry ink — the box grown by its stroke band, its unclipped children's
///   painted extents, its shadows and its blur. Never an input to layout.
///
/// ``PenLayoutEngine/placement(of:rect:layoutRects:)`` answers in the parent's
/// coordinates, ``PenLayoutEngine/canvasPlacement(of:in:layoutRects:)`` in the canvas's.
public struct PenPlacement: Friendly {
    /// The node's box, in its own coordinates — the space its children's rects are
    /// measured in (``PenLayoutEngine/unturnedBox(of:rect:layoutRects:)``).
    public var box: PenRect

    /// The map from the node's own coordinates to the target space.
    public var transform: PenLayoutEngine.PlaneTransform

    /// Creates a placement.
    ///
    /// - Parameters:
    ///   - box: The node's box, in its own coordinates.
    ///   - transform: The map from its own coordinates to the target space.
    public init(box: PenRect, transform: PenLayoutEngine.PlaneTransform) {
        self.box = box
        self.transform = transform
    }

    /// The box's corners in the target space, clockwise from its own top-left: top-left,
    /// top-right, bottom-right, bottom-left. A flip reverses their winding on the page.
    public var corners: [PenPoint] {
        [
            PenPoint(x: box.x, y: box.y),
            PenPoint(x: box.x + box.width, y: box.y),
            PenPoint(x: box.x + box.width, y: box.y + box.height),
            PenPoint(x: box.x, y: box.y + box.height),
        ].map(transform.apply(to:))
    }

    /// The axis-aligned bounds of the drawn quad in the target space: in the parent's
    /// coordinates, the node's layout rect (extent (i)).
    public var bounds: PenRect {
        transform.bounds(of: box)
    }

    /// This placement carried one space further out: the same box, its map followed by
    /// `outer`.
    ///
    /// - Parameter outer: The map from this placement's target space to the next — a
    ///   parent's own placement, say, to go from grandparent-relative to canvas.
    /// - Returns: The composed placement.
    public func placed(in outer: PenLayoutEngine.PlaneTransform) -> PenPlacement {
        PenPlacement(box: box, transform: outer.concatenating(transform))
    }
}
