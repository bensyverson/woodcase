//
//  PenLayoutEngine+ConnectionHitTest.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// Whether `point` falls on what a connection paints: the stroke band along its
    /// route and its arrowheads (``PenNode/ConnectionData/Drawing/contains(_:tolerance:)``).
    ///
    /// A connection's layout rect is no part of where it draws, so an editor hit-tests it
    /// here rather than through ``strokeBandContains(_:of:box:)``. The gate is that one's:
    /// a connection with no visible stroke paint, or a disabled one, is never hit.
    ///
    /// - Parameters:
    ///   - point: The point, on the canvas.
    ///   - node: The connection.
    ///   - canvasRects: Every node's box on the canvas (``connectionEndpointRects(in:layoutRects:)``).
    ///   - tolerance: How far outside the painted shape still counts, in points.
    /// - Returns: `false` for a node that is not a connection, one whose endpoint names no
    ///   node, or one that paints nothing.
    static func connectionBandContains(
        _ point: PenPoint, of node: PenNode, canvasRects: [String: PenRect], tolerance: Double = 0
    ) -> Bool {
        guard case let .connection(data) = node.kind, node.common.enabled?.literalValue != false,
              data.stroke?.hasVisiblePaint == true,
              let drawing = node.connectionDrawing(in: canvasRects)
        else { return false }
        return drawing.contains(point, tolerance: tolerance)
    }

    /// Everything a connection paints, on the canvas: its route's stroke band and its
    /// arrowheads (``PenNode/ConnectionData/Drawing/paintedExtent``).
    ///
    /// ``paintedExtent(of:rect:layoutRects:)`` measures a node from its layout rect, which a
    /// connection's says nothing about; this measures it from its endpoints.
    ///
    /// - Parameters:
    ///   - node: The connection.
    ///   - canvasRects: Every node's box on the canvas (``connectionEndpointRects(in:layoutRects:)``).
    /// - Returns: The extent, or `nil` for a node that is not a connection, or one whose
    ///   endpoint names no node or whose stroke width is per side.
    static func connectionPaintedExtent(of node: PenNode, canvasRects: [String: PenRect]) -> PenRect? {
        node.connectionDrawing(in: canvasRects)?.paintedExtent
    }
}
