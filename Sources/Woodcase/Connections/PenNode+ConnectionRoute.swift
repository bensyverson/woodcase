//
//  PenNode+ConnectionRoute.swift
//  Woodcase
//

import Foundation

public extension PenNode.ConnectionData {
    /// The points a connection's stroke runs through, from its source's anchor to its
    /// target's, on the canvas.
    ///
    /// Straight is the two anchors; an elbow adds the corners of an orthogonal route. This
    /// is the connection's centerline before arrowheads: ``Drawing`` cuts it back where an
    /// arrowhead covers an end.
    struct Route: Friendly {
        /// Creates a route.
        ///
        /// - Parameter points: The points, from the source's anchor to the target's.
        public init(points: [PenPoint]) {
            self.points = points
        }

        /// The points, from the source's anchor to the target's: at least two.
        public var points: [PenPoint]

        /// How far an elbow runs out from a box before it turns, and clears a box it goes
        /// round by, when no arrowhead needs more: 16 points.
        public static let elbowMargin = 16.0
    }

    /// The route from the source's anchor to the target's.
    ///
    /// The rects must all be in one coordinate frame — the canvas, for a connection, which
    /// Pen allows only at the top level: ``PenLayoutEngine/canvasRects(in:layoutRects:)``
    /// composes them from the layout engine's parent-relative ones. An elbow routes round
    /// the two endpoint boxes, leaving and entering perpendicular to the anchors' sides;
    /// the same rects always give the same points.
    ///
    /// - Parameters:
    ///   - rects: Node boxes keyed by id, an expanded instance's descendants by their
    ///     `instance/child` path.
    ///   - routing: How the connection runs between its anchors
    ///     (``PenNode/connectionStyle``'s).
    ///   - margin: How far an elbow runs out from a box before it turns; a drawing passes
    ///     ``Style/elbowMargin(strokeWidth:)``, so a run is never shorter than its arrowhead.
    /// - Returns: The route, or `nil` when either endpoint names a node `rects` lacks.
    func route(in rects: [String: PenRect], routing: Routing, margin: Double = Route.elbowMargin) -> Route? {
        guard let from = rects[source.path], let to = rects[target.path] else { return nil }
        let start = source.anchor.point(on: from)
        let end = target.anchor.point(on: to)
        switch routing {
        case .straight:
            return Route(points: [start, end])
        case .elbow:
            return Route(points: ConnectionElbowRouter.route(
                from: start, side: source.anchor, box: from, to: end, side: target.anchor, box: to, margin: margin
            ))
        }
    }
}

public extension PenNode {
    /// A connection's route on the canvas, routed as its ``connectionStyle`` says — the
    /// route ``connectionDrawing(in:)`` draws — or `nil` for a node that is not a connection
    /// or whose endpoint names a node `canvasRects` lacks.
    ///
    /// - Parameter canvasRects: Every node's box on the canvas
    ///   (``PenLayoutEngine/canvasRects(in:layoutRects:)``).
    /// - Returns: The route.
    func connectionRoute(in canvasRects: [String: PenRect]) -> ConnectionData.Route? {
        guard case let .connection(data) = kind, let style = connectionStyle else { return nil }
        let width = data.uniformStrokeWidth ?? 1
        return data.route(in: canvasRects, routing: style.routing, margin: style.elbowMargin(strokeWidth: width))
    }
}
