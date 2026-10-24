//
//  PenNode+ConnectionDrawing.swift
//  Woodcase
//

import Foundation

public extension PenNode.ConnectionData {
    /// Everything a connection paints, as geometry on the canvas: the line it strokes and
    /// the arrowheads at its ends, all in the stroke's paint.
    ///
    /// This is the one description every renderer draws from — Woodcase's CoreGraphics
    /// renderer, RapidPro — so they agree by construction: stroke ``line`` at
    /// ``strokeWidth`` with ``strokeLinecap`` and ``strokeLinejoin``, centered on it
    /// (alignment plays no part: a connector has no inside to align to), then draw
    /// ``start`` and ``end`` as their ``Arrowhead/Shape`` cases say; lay any gradient or
    /// image paint over ``paintDomain``. It also gives an editor the connection's hit test
    /// (``contains(_:tolerance:)``) and its ``paintedExtent``, which its layout rect —
    /// meaningless for a connection — cannot.
    struct Drawing: Friendly {
        /// Creates a drawing.
        ///
        /// - Parameters:
        ///   - route: The route, anchor to anchor.
        ///   - line: The polyline the stroke paints.
        ///   - start: The arrowhead at the source end, or `nil` for none.
        ///   - end: The arrowhead at the target end, or `nil` for none.
        ///   - strokeWidth: The stroke's width.
        ///   - strokeLinecap: How the line's and a chevron's ends are capped.
        ///   - strokeLinejoin: How their corners are joined.
        public init(
            route: Route, line: [PenPoint], start: Arrowhead.Shape?, end: Arrowhead.Shape?,
            strokeWidth: Double, strokeLinecap: PenStrokeCap?, strokeLinejoin: PenStrokeJoin?
        ) {
            self.route = route
            self.line = line
            self.start = start
            self.end = end
            self.strokeWidth = strokeWidth
            self.strokeLinecap = strokeLinecap
            self.strokeLinejoin = strokeLinejoin
        }

        /// The route, anchor to anchor.
        public var route: Route
        /// The polyline the stroke paints: the route, cut back at each end an arrowhead
        /// covers, so a thick line's end never shows past the arrowhead's tip.
        public var line: [PenPoint]
        /// The arrowhead at the source end, or `nil` for none.
        public var start: Arrowhead.Shape?
        /// The arrowhead at the target end, or `nil` for none.
        public var end: Arrowhead.Shape?
        /// The stroke's width, in points.
        public var strokeWidth: Double
        /// How the line's and a chevron's ends are capped; `nil` is butt.
        public var strokeLinecap: PenStrokeCap?
        /// How their corners are joined; `nil` is miter.
        public var strokeLinejoin: PenStrokeJoin?

        /// The box a gradient or image stroke paint is laid out over: the route's bounds,
        /// as a straight connection's segment box always was.
        public var paintDomain: PenRect {
            let xs = route.points.map(\.x)
            let ys = route.points.map(\.y)
            let (minX, minY) = (xs.min() ?? 0, ys.min() ?? 0)
            return PenRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
        }

        /// The arrowheads drawn, start first.
        public var arrowheads: [Arrowhead.Shape] {
            [start, end].compactMap(\.self)
        }
    }

    /// What the connection paints, routed and tipped as `style` says.
    ///
    /// - Parameters:
    ///   - rects: Node boxes on the canvas, keyed by id, an expanded instance's descendants
    ///     by their `instance/child` path (``PenLayoutEngine/connectionEndpointRects(in:layoutRects:)``).
    ///   - style: The routing and arrowheads (``PenNode/connectionStyle``).
    /// - Returns: The drawing, or `nil` when either endpoint names a node `rects` lacks or
    ///   the stroke's width is per side, which no connector draws. A stroke of no width
    ///   gets no arrowheads.
    func drawing(in rects: [String: PenRect], style: Style) -> Drawing? {
        guard let width = uniformStrokeWidth,
              let route = route(in: rects, routing: style.routing, margin: style.elbowMargin(strokeWidth: width))
        else { return nil }
        var line = route.points
        let reversed = Array(line.reversed())
        // A stroke too thin to paint paints no arrowheads either.
        let style = width > 0 ? style : Style(routing: style.routing, startArrowhead: .none, endArrowhead: .none)
        let endHead = Self.direction(into: line).flatMap {
            style.endArrowhead.shape(at: line[line.count - 1], direction: $0, width: width, join: strokeLinejoin)
        }
        let startHead = Self.direction(into: reversed).flatMap {
            style.startArrowhead.shape(at: line[0], direction: $0, width: width, join: strokeLinejoin)
        }
        if let cut = endHead?.cut { line = Self.cutting(line, by: cut) }
        if let cut = startHead?.cut { line = Self.cutting(line.reversed(), by: cut).reversed() }
        return Drawing(
            route: route, line: line, start: startHead?.shape, end: endHead?.shape,
            strokeWidth: width, strokeLinecap: strokeLinecap, strokeLinejoin: strokeLinejoin
        )
    }

    /// The unit direction a polyline runs as it reaches its last point, from its last run
    /// of any length, or `nil` when every point is the same.
    private static func direction(into points: [PenPoint]) -> PenPoint? {
        guard let last = points.last else { return nil }
        for point in points.dropLast().reversed() {
            let (dx, dy) = (last.x - point.x, last.y - point.y)
            let length = (dx * dx + dy * dy).squareRoot()
            if length > 0 { return PenPoint(x: dx / length, y: dy / length) }
        }
        return nil
    }

    /// The polyline with `distance` taken off its end, along its runs; at least its first
    /// point, twice, when it is shorter than that.
    private static func cutting(_ points: [PenPoint], by distance: Double) -> [PenPoint] {
        var points = points
        var remaining = distance
        while remaining > 0, points.count >= 2 {
            let last = points[points.count - 1]
            let before = points[points.count - 2]
            let (dx, dy) = (last.x - before.x, last.y - before.y)
            let length = (dx * dx + dy * dy).squareRoot()
            if length > remaining {
                points[points.count - 1] = PenPoint(
                    x: last.x - dx / length * remaining, y: last.y - dy / length * remaining
                )
                remaining = 0
            } else {
                points.removeLast()
                remaining -= length
            }
        }
        if points.count == 1 { points.append(points[0]) }
        return points
    }
}

public extension PenNode {
    /// What a connection paints on the canvas, routed and tipped as its ``connectionStyle``
    /// says, or `nil` for a node that is not a connection, whose endpoint names a node
    /// `canvasRects` lacks, or whose stroke width is per side.
    ///
    /// - Parameter canvasRects: Every node's box on the canvas
    ///   (``PenLayoutEngine/connectionEndpointRects(in:layoutRects:)``).
    /// - Returns: The drawing.
    func connectionDrawing(in canvasRects: [String: PenRect]) -> ConnectionData.Drawing? {
        guard case let .connection(data) = kind, let style = connectionStyle else { return nil }
        return data.drawing(in: canvasRects, style: style)
    }
}
