import CoreGraphics

extension PenRenderer {
    /// The effects and overrides one node draws its own content with.
    struct OwnContent: Friendly {
        /// The node's draw rect: zero-origin, in the node's own space.
        let drawRect: PenRect
        /// The node's enabled outer shadows, in array order.
        let outerShadows: [PenEffect.PenShadowEffect]
        /// The node's enabled inner shadows, in array order.
        let innerShadows: [PenEffect.PenShadowEffect]
        /// An animation override of the node's fills.
        let overrideFills: PenFills?
    }

    /// Renders a node's own content — everything but its children — in Pen's paint order:
    /// outer shadows, fills, inner shadows, stroke. The caller draws the children after.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - own: Its draw rect, shadows and fill override.
    ///   - groupSilhouette: Draws a group's silhouette, which casts its shadows; ignored for
    ///     any other node.
    ///   - imageProvider: Resolves image paints.
    ///   - context: The context to draw into.
    static func renderOwnContent(
        _ node: PenNode,
        _ own: OwnContent,
        groupSilhouette: (CGContext) -> Void,
        imageProvider: ImageProvider,
        in context: CGContext
    ) {
        let rect = own.drawRect
        if !own.outerShadows.isEmpty {
            let bounds = rect.cgRect.insetBy(dx: -outerStrokeReach(of: node), dy: -outerStrokeReach(of: node))
            PenEffectRenderer.renderOuterShadows(own.outerShadows, bounds: bounds, in: context) { target in
                PenShadowSilhouette.draw(
                    node, rect: rect, in: target, children: groupSilhouette, imageProvider: imageProvider
                )
            }
        }

        switch node.kind {
        case let .frame(data):
            renderShape(
                fills: own.overrideFills ?? data.fills, stroke: data, node: node, own, imageProvider: imageProvider, in: context
            )
        case let .rectangle(data):
            renderShape(
                fills: own.overrideFills ?? data.fills, stroke: data, node: node, own, imageProvider: imageProvider, in: context
            )
        case let .ellipse(data):
            renderShape(
                fills: own.overrideFills ?? data.fills, stroke: data, node: node, own, imageProvider: imageProvider, in: context
            )
        case let .polygon(data):
            renderShape(
                fills: own.overrideFills ?? data.fills, stroke: data, node: node, own, imageProvider: imageProvider, in: context
            )
        case let .path(data):
            renderShape(
                fills: own.overrideFills ?? data.fills, stroke: data, node: node, own, imageProvider: imageProvider, in: context
            )
        case let .line(data):
            guard let path = PenShapeBuilder.buildPath(for: node, rect: rect) else { return }
            // Lines only have strokes, no fills
            let stroke = data.drawn(on: node)
            PenStrokeRenderer.renderStroke(
                stroke, path: path, rect: lineBand(rect, strokeWidth: stroke.uniformStrokeWidth ?? 1),
                in: context, imageProvider: imageProvider
            )
        case let .text(data):
            PenTextRenderer.renderText(
                data: data, rect: rect, fills: own.overrideFills ?? data.fills,
                in: context, imageProvider: imageProvider
            )
            renderGlyphInnerShadows(own.innerShadows, node: node, rect: rect, imageProvider: imageProvider, in: context)
        case let .icon(data):
            PenIconFontRenderer.render(
                data: data, rect: rect, fills: own.overrideFills ?? data.fills,
                in: context, imageProvider: imageProvider
            )
            renderGlyphInnerShadows(own.innerShadows, node: node, rect: rect, imageProvider: imageProvider, in: context)
        case let .browser(data):
            PenBrowserPlaceholder.render(data, node: node, rect: rect, in: context)
            renderInnerShadows(own.innerShadows, node: node, rect: rect, in: context)
        default:
            break // A group's inner shadows follow its children; scripts are not executed.
        }
    }

    /// Fills, then inner shadows, then the stroke — so an inner shadow sits under the stroke,
    /// and under the children the caller draws next.
    private static func renderShape(
        fills: PenFills?,
        stroke: any PenStrokable,
        node: PenNode,
        _ own: OwnContent,
        imageProvider: ImageProvider,
        in context: CGContext
    ) {
        guard let path = PenShapeBuilder.buildPath(for: node, rect: own.drawRect) else { return }
        PenFillRenderer.renderFills(
            fills,
            clip: path, fillRule: PenShapeBuilder.fillRule(for: node), domain: own.drawRect.cgRect,
            in: context, imageProvider: imageProvider
        )
        for shadow in own.innerShadows {
            PenEffectRenderer.renderInnerShadow(shadow, path: path, fillRule: PenShapeBuilder.fillRule(for: node), in: context)
        }
        PenStrokeRenderer.renderStroke(
            stroke.drawn(on: node), path: path, rect: own.drawRect,
            roundedBox: PenStrokeRenderer.roundedBox(for: node, rect: own.drawRect),
            in: context, imageProvider: imageProvider
        )
    }

    /// Inner shadows for a node that is not one of the stroked shapes but still has a path.
    private static func renderInnerShadows(
        _ shadows: [PenEffect.PenShadowEffect], node: PenNode, rect: PenRect, in context: CGContext
    ) {
        guard !shadows.isEmpty, let path = PenShapeBuilder.buildPath(for: node, rect: rect) else { return }
        for shadow in shadows {
            PenEffectRenderer.renderInnerShadow(shadow, path: path, in: context)
        }
    }

    /// A text or icon node's inner shadows, inside its glyphs and over its fill.
    ///
    /// Pen casts them from the glyphs drawn opaque, whatever the paint: a translucent fill,
    /// or none, still shows the shadow at full strength (`render-text-shadows.pen`); an
    /// icon's glyph the same way (`render-inner-shadow-shapes.pen`, the `icon-*` boards).
    private static func renderGlyphInnerShadows(
        _ shadows: [PenEffect.PenShadowEffect], node: PenNode, rect: PenRect,
        imageProvider: ImageProvider, in context: CGContext
    ) {
        for shadow in shadows {
            PenEffectRenderer.renderInnerShadow(shadow, bounds: rect.cgRect, in: context) { target in
                PenShadowSilhouette.draw(node, rect: rect, in: target, children: { _ in }, imageProvider: imageProvider)
            }
        }
    }

    /// How far a node's stroke can reach outside its box, for the shadow's silhouette bounds.
    private static func outerStrokeReach(of node: PenNode) -> CGFloat {
        let stroke: (any PenStrokable)? = switch node.kind {
        case let .frame(data): data
        case let .rectangle(data): data
        case let .ellipse(data): data
        case let .polygon(data): data
        case let .path(data): data
        case let .line(data): data
        default: nil
        }
        let widths: [Double] = switch stroke?.strokeWidth {
        case let .uniform(value): [value.literalValue ?? 1]
        case let .perSide(sides): [sides.top, sides.right, sides.bottom, sides.left].compactMap { $0?.literalValue }
        case nil: [stroke == nil ? 0 : 1]
        }
        return CGFloat(2 * (widths.max() ?? 0))
    }

    /// The box a line's stroke paint is laid over: the line's own box, or — on an axis where
    /// the line has no extent, which would collapse the paint's geometry to nothing — the
    /// stroke's band across it. Pen lays the paint over the zero-height box and so collapses
    /// a ramp across a flat line to a split or black; Woodcase paints the ramp over the band
    /// (<doc:PenInteroperability>, *Kept Divergences*; `render-painted-lines.pen`).
    static func lineBand(_ rect: PenRect, strokeWidth: Double) -> PenRect {
        PenRect(
            x: rect.width == 0 ? rect.x - strokeWidth / 2 : rect.x,
            y: rect.height == 0 ? rect.y - strokeWidth / 2 : rect.y,
            width: rect.width == 0 ? strokeWidth : rect.width,
            height: rect.height == 0 ? strokeWidth : rect.height
        )
    }
}
