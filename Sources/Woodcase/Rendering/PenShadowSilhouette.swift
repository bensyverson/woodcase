import CoreGraphics

/// The shape a node's outer shadow is cast by, drawn in opaque ink.
///
/// Pen CLI 0.3.13 casts an outer shadow from what the node paints, each paint drawn opaque:
/// a fill that paints covers the shape however translucent it is (a quarter-alpha fill casts
/// a full-strength shadow), and a disabled or fully transparent fill covers nothing; a stroke
/// that paints covers its band — outside, across or inside the outline as it is aligned — and
/// a line's stroke casts like any other. A frame's and a group's children cast through it
/// (``PenRenderer/drawDescendantSilhouettes(of:clip:layoutRects:overrides:imageProvider:in:)``),
/// so a frame with no fill casts its children's shadows and not its box
/// (`render-content-shadows.pen`; `render-shadows.pen`, `outer-frame-children`).
///
/// Pen 1.2.16 (CLI 0.3.11) cast a frame's box, nothing of its children, and nothing of a
/// line; `project/2026-10-23-pen-cli-0.3.13.md` records the change.
enum PenShadowSilhouette {
    /// The ink a silhouette is drawn in: opaque black. Only its coverage matters.
    static let ink = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 0, 1])!

    /// The region a shape node's own paint covers: its outline where a fill paints, united
    /// with its stroke's band where the stroke paints.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: The node's draw rect.
    /// - Returns: The silhouette and the rule to fill it with, or `nil` for a node whose own
    ///   paint covers nothing, or that is not a shape (text, icon, group).
    static func path(for node: PenNode, rect: PenRect) -> (path: CGPath, rule: CGPathFillRule)? {
        guard let shape = PenShapeBuilder.buildPath(for: node, rect: rect) else { return nil }
        let rule = PenShapeBuilder.fillRule(for: node)
        let filled = paintsInterior(node)
        let band = strokable(node).flatMap { strokeBand(of: $0.drawn(on: node), shape: shape, node: node, rect: rect) }
        switch (filled, band) {
        case let (true, band?): return (shape.union(band, using: rule), .winding)
        case (true, nil): return (shape, rule)
        case let (false, band?): return (band, .winding)
        case (false, nil): return nil
        }
    }

    /// Draws the silhouette of `node` in ``ink``, then its descendants'.
    ///
    /// A shape's own silhouette is grown by `spread` (``spread(_:rule:by:)``). A text's and an
    /// icon's glyphs, and a frame's or a group's descendants, are drawn as they are: a spread
    /// does not grow them.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: The node's draw rect.
    ///   - spread: How far to grow a shape's own silhouette, in points; negative shrinks it.
    ///   - context: The context to draw into.
    ///   - children: Draws the node's descendants' silhouettes, after its own: a frame's
    ///     children, clipped as it clips, or a group's.
    ///   - imageProvider: Resolves image paints for text and icons.
    static func draw(
        _ node: PenNode,
        rect: PenRect,
        spread: CGFloat,
        in context: CGContext,
        children: (CGContext) -> Void,
        imageProvider: PenRenderer.ImageProvider
    ) {
        let ink = PenFills.single(.shorthand("#000000"))
        if let silhouette = path(for: node, rect: rect) {
            let grown = Self.spread(silhouette.path, rule: silhouette.rule, by: spread)
            context.addPath(grown.path)
            context.setFillColor(Self.ink)
            context.fillPath(using: grown.rule)
        } else if case .text = node.kind {
            PenTextRenderer.renderText(node: node, rect: rect, fills: ink, in: context, imageProvider: imageProvider)
        } else if case let .icon(data) = node.kind {
            PenIconFontRenderer.render(data: data, rect: rect, fills: ink, in: context, imageProvider: imageProvider)
        }
        children(context)
    }

    /// `path` grown by `spread` on every side — or, for a negative spread, shrunk — as a CSS
    /// `box-shadow` spread grows its box: a sharp corner stays sharp, a rounded one's radius
    /// grows with it.
    ///
    /// - Parameters:
    ///   - path: The region.
    ///   - rule: The rule `path` is filled with.
    ///   - spread: How far to grow it, in points.
    /// - Returns: The grown region and the rule to fill it with; `path` itself for no spread.
    static func spread(_ path: CGPath, rule: CGPathFillRule, by spread: CGFloat) -> (path: CGPath, rule: CGPathFillRule) {
        guard spread != 0, spread.isFinite else { return (path, rule) }
        let band = path.copy(strokingWithWidth: abs(spread) * 2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        return spread > 0
            ? (path.union(band, using: rule), .winding)
            : (path.subtracting(band, using: rule), .winding)
    }

    /// Whether the node's shape is an open line, which covers only what its stroke does.
    private static func isOpen(_ node: PenNode) -> Bool {
        if case .line = node.kind { return true }
        return false
    }

    /// Whether the node paints the inside of its shape: a shape kind when one of its fills
    /// paints, a line never, and any other kind with a shape — a browser's placeholder —
    /// always.
    private static func paintsInterior(_ node: PenNode) -> Bool {
        switch node.kind {
        case .line: false
        case .frame, .rectangle, .ellipse, .polygon, .path: PenRenderer.fills(for: node)?.hasVisiblePaint == true
        default: true
        }
    }

    /// The node's stroke keys, for the shape kinds that carry them.
    private static func strokable(_ node: PenNode) -> (any PenStrokable)? {
        switch node.kind {
        case let .frame(data): data
        case let .rectangle(data): data
        case let .ellipse(data): data
        case let .polygon(data): data
        case let .path(data): data
        case let .line(data): data
        default: nil
        }
    }

    /// The region a stroke covers — outside, across or inside the outline as it is aligned,
    /// a line's always across it — or `nil` when it paints nothing.
    private static func strokeBand(
        of stroke: any PenStrokable, shape: CGPath, node: PenNode, rect: PenRect
    ) -> CGPath? {
        guard stroke.stroke?.hasVisiblePaint == true else { return nil }
        let alignment: PenStrokeAlign = isOpen(node) ? .center : stroke.strokeAlignment ?? .center
        if case let .perSide(sides) = stroke.strokeWidth {
            guard let box = PenStrokeRenderer.roundedBox(for: node, rect: rect) else { return nil }
            let widths = PenStrokeRenderer.SideWidths(sides)
            return widths.isEmpty ? nil : PenStrokeRenderer.perSideRing(widths: widths, alignment: alignment, box: box)
        }
        guard let width = stroke.uniformStrokeWidth.map({ CGFloat($0) }), width > 0 else { return nil }
        let box = isOpen(node) ? nil : PenStrokeRenderer.roundedBox(for: node, rect: rect)
        if let band = PenStrokeRenderer.zeroAreaBand(width: width, alignment: alignment, box: box) {
            return band
        }
        let style = PenStrokeRenderer.Style(
            width: width, alignment: alignment, penJoin: stroke.strokeLinejoin, penCap: stroke.strokeLinecap,
            miterLimit: CGFloat(node.strokeMiterLimit)
        )
        let outline = shape.copy(
            strokingWithWidth: style.outlineWidth, lineCap: style.cap, lineJoin: style.join,
            miterLimit: style.miterLimit
        )
        let rule = PenShapeBuilder.fillRule(for: node)
        return switch alignment {
        case .center: outline
        case .outer: outline.subtracting(shape, using: rule)
        case .inner: outline.intersection(shape, using: rule)
        }
    }
}
