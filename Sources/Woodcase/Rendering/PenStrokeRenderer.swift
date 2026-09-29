import CoreGraphics

/// Renders strokes on shape paths.
///
/// A stroke is painted like a fill: its **outline** — the band the stroke covers — is the
/// clip, and the node's **box** is the paint domain, whatever the alignment. So a gradient
/// stroke puts its stops on the node's edges (and pads beyond them, as an outer stroke
/// does), and an image stroke is placed over the box and draws nothing outside the placed
/// image. See ``PenFillRenderer`` for the clip/domain seam both share.
enum PenStrokeRenderer {
    /// Renders a node's stroke for a shape path into the given context.
    ///
    /// Reads the .pen 2.17 flat keys off the node payload: a node with no `stroke` paint
    /// draws nothing, and absent alignment, join and cap keys mean center, miter and butt.
    /// Every paint `PenFillRenderer` draws — stacked, translucent and blended fills
    /// included — is drawn through the stroke's outline, laid out over `rect`.
    ///
    /// - Parameters:
    ///   - node: The node payload carrying the stroke keys.
    ///   - path: The node's shape.
    ///   - rect: The node's box: the domain the stroke's paint is laid out over.
    ///   - roundedBox: The node's box and corner radii when it is box-shaped (see
    ///     ``roundedBox(for:rect:)``); a per-side stroke is laid out on it. Any other shape
    ///     is handed its stroke as ``PenStrokable/drawn(on:)`` gives it, uniform; a per-side
    ///     width without a box draws nothing.
    ///   - context: The context to draw into.
    ///   - imageProvider: Resolves an image paint's URL to an image.
    static func renderStroke(
        _ node: (any PenStrokable)?,
        path: CGPath,
        rect: PenRect,
        roundedBox: RoundedBox? = nil,
        in context: CGContext,
        imageProvider: PenRenderer.ImageProvider = { _ in nil }
    ) {
        guard let node, let fills = node.stroke else { return }
        let domain = rect.cgRect
        func paint(_ region: CGPath, _ fillRule: CGPathFillRule) {
            PenFillRenderer.renderFills(
                fills, clip: region, fillRule: fillRule, domain: domain,
                in: context, imageProvider: imageProvider
            )
        }

        if case let .perSide(sides) = node.strokeWidth, let roundedBox {
            let widths = SideWidths(sides)
            guard !widths.isEmpty else { return }
            paint(perSideRing(widths: widths, alignment: node.strokeAlignment ?? .center, box: roundedBox), .evenOdd)
            return
        }

        guard let width = node.uniformStrokeWidth.map({ CGFloat($0) }), width > 0 else { return }
        let style = Style(
            width: width,
            alignment: node.strokeAlignment ?? .center,
            penJoin: node.strokeLinejoin,
            penCap: node.strokeLinecap
        )
        if let band = zeroAreaBand(width: width, alignment: style.alignment, box: roundedBox) {
            paint(band, .evenOdd)
            return
        }

        if let color = singleSolidColor(fills) {
            renderSolid(color, path: path, style: style, in: context)
        } else {
            renderPainted(paint: paint, path: path, style: style, in: context)
        }
    }

    /// A single solid color is stroked directly with `strokePath()`, as it always was, so
    /// every solid stroke keeps its exact pixels.
    private static func renderSolid(_ color: CGColor, path: CGPath, style: Style, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineJoin(style.join)
        context.setLineCap(style.cap)
        clipToAlignment(style, path: path, outerBounds: style.solidOuterBounds(of: path), in: context)
        context.setLineWidth(style.outlineWidth)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// Any other paint fills the stroke's outline — the stroked path, doubled in width and
    /// cut to the shape or its complement for inner and outer strokes.
    private static func renderPainted(
        paint: (CGPath, CGPathFillRule) -> Void,
        path: CGPath,
        style: Style,
        in context: CGContext
    ) {
        let outline = path.copy(
            strokingWithWidth: style.outlineWidth,
            lineCap: style.cap,
            lineJoin: style.join,
            miterLimit: Style.miterLimit
        )
        context.saveGState()
        clipToAlignment(
            style, path: path,
            outerBounds: style.solidOuterBounds(of: path).union(outline.boundingBox).insetBy(dx: -1, dy: -1),
            in: context
        )
        paint(outline, .winding)
        context.restoreGState()
    }

    /// Clips to the shape for an inner stroke, or to its complement within `outerBounds`
    /// for an outer one; a centered stroke is not clipped.
    private static func clipToAlignment(_ style: Style, path: CGPath, outerBounds: CGRect, in context: CGContext) {
        switch style.alignment {
        case .center:
            break
        case .inner:
            context.addPath(path)
            context.clip()
        case .outer:
            context.addRect(outerBounds)
            context.addPath(path)
            context.clip(using: .evenOdd)
        }
    }
}
