//
//  PenLayoutEngine+CanvasTransform.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// The affine map from a node's own coordinates to the canvas: where ``PenRenderer``
    /// draws each point of it. The map of ``canvasPlacement(of:in:layoutRects:)``, which
    /// carries the box beside it.
    ///
    /// A node's own coordinates are the space its children's rects are measured in: its
    /// unturned box (``unturnedBox(of:rect:layoutRects:)``) starts at their origin — for a
    /// group, which is placed from its anchor, the box is its children's union and may
    /// start anywhere. The map composes, from the root down, each node's placement in its
    /// parent: its box centered in its layout rect, flipped, then turned by Pen's
    /// counter-clockwise degrees about that center — `PenRenderer`'s own composition, and
    /// the one ``absoluteRects(under:in:layoutRects:)`` takes the bounds of. So the map
    /// sends the node's box to the turned quad it is drawn as, whose bounds are its
    /// ``canvasRects(in:layoutRects:)`` rect.
    ///
    /// A node's `x`/`y` is measured in its **parent**'s own coordinates, so the map that
    /// carries a canvas point or delta into the space a node is positioned in is the
    /// inverse of its parent's map (``PlaneTransform/inverted()``); for a root, whose
    /// parent is the canvas, it is the identity. A delta has no position: use the inverse's
    /// linear part, `a`, `b`, `c`, `d`, alone.
    ///
    /// - Parameters:
    ///   - nodeID: The node, in the expanded document's spelling — see
    ///     ``EditableDocument/expandedID(of:)``.
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: The map, or `nil` when the document has no such node, or the layout
    ///   settled no rect for it or for one of its ancestors.
    static func canvasTransform(
        of nodeID: String,
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> PlaneTransform? {
        canvasPlacement(of: nodeID, in: document, layoutRects: layoutRects)?.transform
    }
}
