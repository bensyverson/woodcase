//
//  PenConnectionRenderer.swift
//  Woodcase
//

import CoreGraphics

/// Draws a `connection` node: its route from its source's anchor to its target's —
/// straight, or an elbow — and its arrowheads, painted by the connection's own stroke.
///
/// There is no Pen rendering to match. Pen 1.2.14's validator accepts a connection, but
/// neither its app nor its headless engine loads one — both drop it when they open the
/// file — so this is Woodcase's own drawing, kept deliberately plain: the route is
/// stroked as a `line` is, so no stroke means nothing drawn, and the connection's
/// opacity applies. The routing and arrowheads are Woodcase's own format extension
/// (``PenNode/connectionStyle``; Penumbra ruling R11). Its `x`, `y`, rotation and flips
/// play no part: a connector is where its endpoints are.
///
/// Pen allows a connection only at the top level, so its endpoints are found in canvas
/// coordinates: ``canvasRects(for:layoutRects:)`` composes the layout engine's
/// parent-relative rects once per render — with ``PenLayoutEngine/connectionEndpointRects(in:layoutRects:)``,
/// which also keys an instance by the path an end names it by — and only when the
/// document has a connection.
enum PenConnectionRenderer {
    /// Every node's box in canvas coordinates, or nothing when the document has no
    /// top-level connection to need them.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document being rendered.
    ///   - layoutRects: The layout engine's parent-relative rects.
    /// - Returns: Boxes keyed by id — an expanded instance's descendants by their
    ///   `instance/child` path, and its root by its instance path too — measured from the
    ///   canvas origin.
    static func canvasRects(for document: PenDocument, layoutRects: [String: PenRect]) -> [String: PenRect] {
        let hasConnection = document.children.contains { node in
            if case .connection = node.kind { true } else { false }
        }
        guard hasConnection else { return [:] }
        return PenLayoutEngine.connectionEndpointRects(in: document, layoutRects: layoutRects)
    }

    /// Draws one connection into `context`, whose CTM must be the canvas's: its line and
    /// arrowheads, from ``PenNode/ConnectionData/Drawing`` — the geometry RapidPro draws too.
    ///
    /// The line is stroked as a `line` is, centered whatever its alignment says (a
    /// connector has no inside); a triangle or circle is filled with the stroke's paint,
    /// and a chevron stroked like the line. Every paint is laid over the route's bounds,
    /// so a connection with no keys — straight, bare — draws exactly the segment it always
    /// did. The opacity applies to the whole, through one transparency layer, so an
    /// arrowhead over its line does not darken where they overlap.
    ///
    /// - Parameters:
    ///   - node: The connection node, for its style (``PenNode/connectionStyle``).
    ///   - data: Its payload.
    ///   - opacity: The connection's effective opacity, or `nil` for opaque.
    ///   - canvasRects: Node boxes in canvas coordinates, from ``canvasRects(for:layoutRects:)``.
    ///   - context: The context to draw into.
    ///   - imageProvider: Resolves an image paint's URL, for an image stroke.
    static func render(
        _ node: PenNode,
        data: PenNode.ConnectionData,
        opacity: Double?,
        canvasRects: [String: PenRect],
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider
    ) {
        guard let fills = data.stroke, let style = node.connectionStyle,
              let drawing = data.drawing(in: canvasRects, style: style), drawing.strokeWidth > 0
        else { return }
        var centered = data
        centered.strokeAlignment = nil
        let box = drawing.paintDomain

        context.saveGState()
        defer { context.restoreGState() }
        let translucent = opacity.map { $0 < 1 } ?? false
        if translucent, let opacity {
            context.setAlpha(CGFloat(opacity))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        PenStrokeRenderer.renderStroke(centered, path: drawing.linePath, rect: box, in: context, imageProvider: imageProvider)
        if let arms = drawing.strokedArrowheadPath {
            PenStrokeRenderer.renderStroke(centered, path: arms, rect: box, in: context, imageProvider: imageProvider)
        }
        if let heads = drawing.filledArrowheadPath {
            PenFillRenderer.renderFills(
                fills, clip: heads, fillRule: .winding, domain: box.cgRect, in: context, imageProvider: imageProvider
            )
        }
        if translucent {
            context.endTransparencyLayer()
        }
    }
}
