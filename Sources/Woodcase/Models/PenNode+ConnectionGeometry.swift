//
//  PenNode+ConnectionGeometry.swift
//  Woodcase
//

import Foundation

public extension PenNode.ConnectionData.Anchor {
    /// Where this anchor lands on a box.
    ///
    /// - Parameter rect: The node's box.
    /// - Returns: The box's center, or the middle of the edge the anchor names.
    func point(on rect: PenRect) -> PenNode.ConnectionData.AnchorPoint {
        let midX = rect.x + rect.width / 2
        let midY = rect.y + rect.height / 2
        return switch self {
        case .center: PenNode.ConnectionData.AnchorPoint(x: midX, y: midY)
        case .top: PenNode.ConnectionData.AnchorPoint(x: midX, y: rect.y)
        case .bottom: PenNode.ConnectionData.AnchorPoint(x: midX, y: rect.y + rect.height)
        case .left: PenNode.ConnectionData.AnchorPoint(x: rect.x, y: midY)
        case .right: PenNode.ConnectionData.AnchorPoint(x: rect.x + rect.width, y: midY)
        }
    }
}

public extension PenNode.ConnectionData {
    /// The straight run from the source's anchor to the target's.
    ///
    /// The rects must all be in one coordinate frame — the canvas, for a connection,
    /// which Pen allows only at the top level: ``PenLayoutEngine/absoluteRects(under:in:layoutRects:)``
    /// composes them from the layout engine's parent-relative ones.
    ///
    /// - Parameter rects: Node boxes keyed by id, an expanded instance's descendants by
    ///   their `instance/child` path.
    /// - Returns: The segment, or `nil` when either endpoint names a node `rects` lacks.
    func segment(in rects: [String: PenRect]) -> Segment? {
        guard let from = rects[source.path], let to = rects[target.path] else { return nil }
        return Segment(from: source.anchor.point(on: from), to: target.anchor.point(on: to))
    }
}
