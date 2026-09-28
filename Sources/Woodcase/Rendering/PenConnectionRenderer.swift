//
//  PenConnectionRenderer.swift
//  Woodcase
//

import CoreGraphics

/// Draws a `connection` node: a straight segment from its source's anchor to its
/// target's, painted by the connection's own stroke.
///
/// There is no Pen rendering to match. Pen 1.2.14's validator accepts a connection, but
/// neither its app nor its headless engine loads one — both drop it when they open the
/// file — so this is Woodcase's own drawing, kept deliberately plain: the segment is
/// stroked exactly as a `line` is, so no stroke means nothing drawn, and the connection's
/// opacity applies. Its `x`, `y`, rotation and flips play no part: a connector is where
/// its endpoints are.
///
/// Pen allows a connection only at the top level, so its endpoints are found in canvas
/// coordinates: ``canvasRects(for:layoutRects:)`` composes the layout engine's
/// parent-relative rects once per render — with ``PenLayoutEngine/canvasRects(in:layoutRects:)`` —
/// and only when the document has a connection.
enum PenConnectionRenderer {
    /// Every node's box in canvas coordinates, or nothing when the document has no
    /// top-level connection to need them.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document being rendered.
    ///   - layoutRects: The layout engine's parent-relative rects.
    /// - Returns: Boxes keyed by id — an expanded instance's descendants by their
    ///   `instance/child` path — measured from the canvas origin.
    static func canvasRects(for document: PenDocument, layoutRects: [String: PenRect]) -> [String: PenRect] {
        let hasConnection = document.children.contains { node in
            if case .connection = node.kind { true } else { false }
        }
        guard hasConnection else { return [:] }
        return PenLayoutEngine.canvasRects(in: document, layoutRects: layoutRects)
    }

    /// Strokes one connection's segment into `context`, whose CTM must be the canvas's.
    ///
    /// - Parameters:
    ///   - data: The connection.
    ///   - opacity: The connection's effective opacity, or `nil` for opaque.
    ///   - canvasRects: Node boxes in canvas coordinates, from ``canvasRects(for:layoutRects:)``.
    ///   - context: The context to draw into.
    ///   - imageProvider: Resolves an image paint's URL, for an image stroke.
    static func render(
        _ data: PenNode.ConnectionData,
        opacity: Double?,
        canvasRects: [String: PenRect],
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider
    ) {
        guard data.stroke != nil, let segment = data.segment(in: canvasRects) else { return }
        let from = CGPoint(x: segment.from.x, y: segment.from.y)
        let to = CGPoint(x: segment.to.x, y: segment.to.y)
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        let box = PenRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y)
        )

        context.saveGState()
        defer { context.restoreGState() }
        let translucent = opacity.map { $0 < 1 } ?? false
        if translucent, let opacity {
            context.setAlpha(CGFloat(opacity))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        PenStrokeRenderer.renderStroke(data, path: path, rect: box, in: context, imageProvider: imageProvider)
        if translucent {
            context.endTransparencyLayer()
        }
    }
}
