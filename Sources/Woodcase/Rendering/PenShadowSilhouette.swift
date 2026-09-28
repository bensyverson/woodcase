import CoreGraphics

/// The shape a node's outer shadow is cast by, drawn in opaque ink.
///
/// Pen 1.2.14 casts an outer shadow from what the node covers, not from what it paints: a
/// quarter-transparent fill casts a full-strength shadow, a frame with no fill casts the
/// shadow of its box, and a frame's children cast nothing of their own. A stroke that
/// reaches outside the shape grows the silhouette by that much. A line casts nothing: it has
/// no interior, and Pen does not cast a shadow from an open stroke — the same rule
/// ``PenRenderer/drawGroupSilhouette(of:layoutRects:overrides:imageProvider:in:)`` already
/// applies to a line inside a group.
enum PenShadowSilhouette {
    /// The ink a silhouette is drawn in: opaque black. Only its coverage matters.
    static let ink = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 0, 1])!

    /// The region a shape node covers: its outline, united with its stroke's outline where
    /// the stroke lies outside the shape.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: The node's draw rect.
    /// - Returns: The silhouette and the rule to fill it with, or `nil` for a node that is not
    ///   a closed shape (text, icon, line, group).
    static func path(for node: PenNode, rect: PenRect) -> (path: CGPath, rule: CGPathFillRule)? {
        guard !isOpen(node), let shape = PenShapeBuilder.buildPath(for: node, rect: rect) else { return nil }
        let rule = PenShapeBuilder.fillRule(for: node)
        guard let stroke = strokable(node)?.drawn(on: node), stroke.stroke != nil,
              let band = outsideBand(of: stroke, shape: shape, node: node, rect: rect)
        else { return (shape, rule) }
        return (shape.union(band, using: rule), .winding)
    }

    /// Draws the silhouette of `node` in ``ink``.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: The node's draw rect.
    ///   - context: The context to draw into.
    ///   - children: Draws a group's silhouette, its descendants' combined outline; called
    ///     for a group only.
    ///   - imageProvider: Resolves image paints for text and icons.
    static func draw(
        _ node: PenNode,
        rect: PenRect,
        in context: CGContext,
        children: (CGContext) -> Void,
        imageProvider: PenRenderer.ImageProvider
    ) {
        let ink = PenFills.single(.shorthand("#000000"))
        if let silhouette = path(for: node, rect: rect) {
            context.addPath(silhouette.path)
            context.setFillColor(Self.ink)
            context.fillPath(using: silhouette.rule)
            return
        }
        switch node.kind {
        case .line:
            break // Pen casts no shadow from a line's stroke.
        case let .text(data):
            PenTextRenderer.renderText(data: data, rect: rect, fills: ink, in: context, imageProvider: imageProvider)
        case let .icon(data):
            PenIconFontRenderer.render(data: data, rect: rect, fills: ink, in: context, imageProvider: imageProvider)
        case .group:
            children(context)
        default:
            break
        }
    }

    /// Whether the node's shape is an open line, which covers only what its stroke does.
    private static func isOpen(_ node: PenNode) -> Bool {
        if case .line = node.kind { return true }
        return false
    }

    /// The node's stroke keys, for the shape kinds that carry them.
    private static func strokable(_ node: PenNode) -> (any PenStrokable)? {
        switch node.kind {
        case let .frame(data): data
        case let .rectangle(data): data
        case let .ellipse(data): data
        case let .polygon(data): data
        case let .path(data): data
        default: nil
        }
    }

    /// The part of the stroke's band that can lie outside the shape, or `nil` when none can.
    private static func outsideBand(
        of stroke: any PenStrokable, shape: CGPath, node: PenNode, rect: PenRect
    ) -> CGPath? {
        let alignment = stroke.strokeAlignment ?? .center
        guard alignment != .inner else { return nil }
        if case let .perSide(sides) = stroke.strokeWidth {
            guard let box = PenStrokeRenderer.roundedBox(for: node, rect: rect) else { return nil }
            let widths = PenStrokeRenderer.SideWidths(sides)
            return widths.isEmpty ? nil : PenStrokeRenderer.perSideRing(widths: widths, alignment: alignment, box: box)
        }
        guard let width = stroke.uniformStrokeWidth.map({ CGFloat($0) }), width > 0 else { return nil }
        let box = PenStrokeRenderer.roundedBox(for: node, rect: rect)
        if let band = PenStrokeRenderer.zeroAreaBand(width: width, alignment: alignment, box: box) {
            return band
        }
        let style = PenStrokeRenderer.Style(
            width: width, alignment: alignment, penJoin: stroke.strokeLinejoin, penCap: stroke.strokeLinecap
        )
        return shape.copy(
            strokingWithWidth: style.outlineWidth, lineCap: style.cap, lineJoin: style.join,
            miterLimit: PenStrokeRenderer.Style.miterLimit
        )
    }
}
