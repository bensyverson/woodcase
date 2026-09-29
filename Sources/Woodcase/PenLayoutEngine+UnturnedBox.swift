//
//  PenLayoutEngine+UnturnedBox.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// A group's box: the union of its enabled children's layout rects, in the group's own
    /// coordinates, whose origin is the group's anchor.
    ///
    /// Pen settles a group at exactly this union, wherever it starts: a group at `(50, 50)`
    /// whose children sit at `(20, 30)` and `(80, 60)` settles at `(70, 80)`, and one whose
    /// child reaches `(-30, -20)` settles that far left of and above its anchor
    /// (`render-free-groups.pen`). The anchor itself is not part of the union. A child's rect
    /// is its turned bounds when it turns, so the union reaches them. A group with no enabled
    /// child is an empty box at its anchor.
    ///
    /// - Parameters:
    ///   - group: The group.
    ///   - rects: Layout rects holding its children's, parent-relative as the engine writes
    ///     them.
    /// - Returns: The union, measured from the group's anchor.
    static func groupBox(of group: PenNode, in rects: [String: PenRect]) -> PenRect {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for child in group.kind.inlineChildren where child.common.enabled?.literalValue != false {
            guard let rect = rects[child.id] else { continue }
            minX = min(minX, rect.x)
            minY = min(minY, rect.y)
            maxX = max(maxX, rect.x + rect.width)
            maxY = max(maxY, rect.y + rect.height)
        }
        guard minX <= maxX, minY <= maxY else { return PenRect(x: 0, y: 0, width: 0, height: 0) }
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A node's unturned box in its own coordinates — the space its children's rects are
    /// measured in — given its layout rect.
    ///
    /// For every node but a group the box starts at the origin, at the rect's
    /// ``PenRect/drawnSize``: the unturned size the layout carried on a turned node's rect,
    /// the rect's own size otherwise. Nothing is solved for — the layout sized the node
    /// before it turned it, and the rect keeps that size. A group's box is its children's
    /// union (``groupBox(of:in:)``), which may start anywhere. A renderer draws this box
    /// centered in the layout rect and turns and flips it about its center; the children
    /// are drawn from the box's coordinates.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: Its layout rect — as settled, or with an animation's overrides applied.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them, for a
    ///     group's children.
    /// - Returns: The box, in the node's own coordinates.
    static func unturnedBox(of node: PenNode, rect: PenRect, layoutRects: [String: PenRect]) -> PenRect {
        if case .group = node.kind {
            return groupBox(of: node, in: layoutRects)
        }
        let size = rect.drawnSize
        return PenRect(x: 0, y: 0, width: size.width, height: size.height)
    }
}
