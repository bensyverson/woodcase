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
    func point(on rect: PenRect) -> PenPoint {
        let midX = rect.x + rect.width / 2
        let midY = rect.y + rect.height / 2
        return switch self {
        case .center: PenPoint(x: midX, y: midY)
        case .top: PenPoint(x: midX, y: rect.y)
        case .bottom: PenPoint(x: midX, y: rect.y + rect.height)
        case .left: PenPoint(x: rect.x, y: midY)
        case .right: PenPoint(x: rect.x + rect.width, y: midY)
        }
    }

    /// The unit direction pointing out of the box through this anchor's side, y growing
    /// downward, or `nil` for the center, which has no side.
    ///
    /// An elbow route leaves its source along this direction and enters its target against it.
    var outwardNormal: PenPoint? {
        switch self {
        case .center: nil
        case .top: PenPoint(x: 0, y: -1)
        case .bottom: PenPoint(x: 0, y: 1)
        case .left: PenPoint(x: -1, y: 0)
        case .right: PenPoint(x: 1, y: 0)
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
