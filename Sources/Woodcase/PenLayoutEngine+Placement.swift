//
//  PenLayoutEngine+Placement.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// A node's placement in its parent: its box in its own coordinates and the map that
    /// carries the box into its parent's — extent (ii) (``PenPlacement``).
    ///
    /// The box is ``unturnedBox(of:rect:layoutRects:)``: `0, 0` at the size the layout gave
    /// the node before it turned it, or, for a group, its children's union measured from
    /// its anchor. The map draws that box centered in the layout rect, flipped, then turned
    /// by Pen's counter-clockwise degrees about that center — which draws the same quad as
    /// Pen's own `translate(x, y) · turn · flip` about the anchor, because a turned box's
    /// bounds are centered on its center. So the map sends the box's corners to the quad the
    /// node is drawn as, and the quad's bounds (``PenPlacement/bounds``) are `rect`'s.
    ///
    /// Every placement-aware reader composes this one answer: ``absoluteRects(under:in:layoutRects:)``
    /// takes the bounds of its compositions, ``canvasPlacement(of:in:layoutRects:)`` composes
    /// it from the root down, and ``paintedExtent(of:rect:layoutRects:)`` carries each
    /// child's ink through it.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: Its layout rect, in its parent's coordinates — as settled, or with an
    ///     animation's overrides applied.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them, for a
    ///     group's children.
    /// - Returns: The node's box and the map into its parent's coordinates.
    static func placement(of node: PenNode, rect: PenRect, layoutRects: [String: PenRect]) -> PenPlacement {
        let box = unturnedBox(of: node, rect: rect, layoutRects: layoutRects)
        return PenPlacement(box: box, transform: PlaneTransform.placing(node, rect: rect, box: box))
    }

    /// A node's placement on the canvas: its box and the map from its own coordinates to
    /// the canvas, composed from the root down (``placement(of:rect:layoutRects:)`` at
    /// every level) — what ``PenRenderer`` draws each point of it with.
    ///
    /// The corners (``PenPlacement/corners``) are the turned quad the node is drawn as, a
    /// hit test's polygon; the bounds are its ``canvasRects(in:layoutRects:)`` rect.
    ///
    /// - Parameters:
    ///   - nodeID: The node, in the expanded document's spelling — see
    ///     ``EditableDocument/expandedID(of:)``.
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: The placement, or `nil` when the document has no such node, or the
    ///   layout settled no rect for it or for one of its ancestors.
    static func canvasPlacement(
        of nodeID: String,
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> PenPlacement? {
        // A work list, not recursion, so a deep tree cannot overflow a Swift task's stack
        // in a debug build (`project/2026-09-26-debug-stack-depth.md`).
        var pending = document.children.reversed().map { (node: $0, parent: PlaneTransform.identity) }
        while let (node, parent) = pending.popLast() {
            guard let rect = layoutRects[node.id] else {
                if node.id == nodeID { return nil }
                continue
            }
            let placed = placement(of: node, rect: rect, layoutRects: layoutRects).placed(in: parent)
            if node.id == nodeID { return placed }
            pending.append(contentsOf: node.kind.inlineChildren.reversed().map { (node: $0, parent: placed.transform) })
        }
        return nil
    }
}
