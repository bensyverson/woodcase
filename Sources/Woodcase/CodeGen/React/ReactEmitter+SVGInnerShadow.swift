//
//  ReactEmitter+SVGInnerShadow.swift
//  Woodcase
//

extension ReactEmitter {
    /// What an inner-shadow filter puts out.
    enum InnerShadowComposite: Friendly {
        /// The coloured shadow alone, kept inside the silhouette: the filter of a copy of an
        /// SVG shape drawn between its fill and its stroke, blended by the copy's
        /// `mix-blend-mode`.
        case shadowOnly
        /// The shadow composited over what the element paints, with the shadow's blend mode:
        /// the CSS filter of an icon, whose glyph is the silhouette.
        case overSource
    }

    /// An inner shadow as an SVG `<filter>`, one line per element.
    ///
    /// The silhouette is cut out of the filter region — the outside, which casts the
    /// shadow inward, as Pen draws it — then offset, blurred, coloured with the shadow's
    /// colour, and kept where the silhouette covers. The outside is a flood with the
    /// silhouette cut away, not the silhouette's alpha inverted: WebKit inverts only
    /// within the silhouette's bounding box, which loses every edge on it (a hexagon's
    /// flanks measured 1.721 against Pen's export that way, 0.036 this way; `scripts/png-mae`
    /// on a `sleepy shot --scale 2` of `render-inner-shadow-shapes-polygon`). Filter lengths are in the user space of the element it is
    /// applied to, so `scale` — points per user unit on each axis — brings the offset and
    /// the Gaussian (σ, half of Pen's `blur`) back to points under a stretching viewBox.
    /// The filter works in sRGB, as Pen and CSS shadows blend.
    ///
    /// - Parameters:
    ///   - shadow: The inner shadow.
    ///   - id: The filter's id.
    ///   - region: The filter region's attributes: it must reach past the silhouette by
    ///     the shadow's offset and blur, or the inverted alpha is cut short at its edge.
    ///   - scale: Points per user unit, x and y.
    ///   - composite: What the filter puts out.
    /// - Returns: The filter's lines.
    static func svgInnerShadowFilter(
        _ shadow: PenEffect.PenShadowEffect,
        id: String,
        region: String,
        scale: SVGStrokedShape.Scale,
        composite: InnerShadowComposite
    ) -> [String] {
        let x = shadow.offset?.x.literalValue ?? 0
        let y = shadow.offset?.y.literalValue ?? 0
        let sigma = (shadow.blur?.literalValue ?? 0) / 2
        let deviation = scale.x == scale.y
            ? svgNumber(sigma / scale.x)
            : "\(svgNumber(sigma / scale.x)) \(svgNumber(sigma / scale.y))"
        let colour = shadow.color.map(cssColorReference) ?? PenEffect.PenShadowEffect.defaultCSSColor
        var lines = [
            "<filter id=\"\(id)\" \(region) colorInterpolationFilters=\"sRGB\">",
            "  <feFlood floodColor=\"black\" />",
            "  <feComposite in2=\"SourceAlpha\" operator=\"out\" />",
            "  <feOffset dx=\"\(svgNumber(x / scale.x))\" dy=\"\(svgNumber(y / scale.y))\" />",
            "  <feGaussianBlur stdDeviation=\"\(deviation)\" result=\"wcInnerBlur\" />",
            "  <feFlood style={{ floodColor: \"\(colour)\" }} />",
            "  <feComposite in2=\"wcInnerBlur\" operator=\"in\" />",
            "  <feComposite in2=\"SourceAlpha\" operator=\"in\" />",
        ]
        if composite == .overSource {
            if let mode = shadow.blendMode, shadow.isBlended {
                lines.append("  <feBlend in2=\"SourceGraphic\" mode=\"\(blendModeToCSSValue(mode))\" />")
            } else {
                lines.append("  <feComposite in2=\"SourceGraphic\" operator=\"over\" />")
            }
        }
        lines.append("</filter>")
        return lines
    }

    /// How far past a silhouette an inner shadow's filter region must reach, in points:
    /// the offset, three standard deviations of the blur, and a pixel to spare.
    static func innerShadowReach(_ shadow: PenEffect.PenShadowEffect) -> Double {
        let x = abs(shadow.offset?.x.literalValue ?? 0)
        let y = abs(shadow.offset?.y.literalValue ?? 0)
        return max(x, y) + 1.5 * (shadow.blur?.literalValue ?? 0) + 1
    }

    /// Writes one filtered copy of `shape` per inner shadow, bottom first: each copy is
    /// filled opaque, which its filter (``svgInnerShadowFilter(_:id:region:scale:composite:)``)
    /// turns into the shadow alone, and carries the shadow's blend mode. The caller writes
    /// them over the fill and under the stroke, where Pen draws them.
    static func emitSVGInnerShadows(
        _ shape: SVGStrokedShape, shadows: [PenEffect.PenShadowEffect], indent: Int, ctx: EmitContext
    ) {
        guard !shadows.isEmpty else { return }
        let pad = String(repeating: " ", count: indent)
        var defs: [String] = []
        var copies: [String] = []
        let rule = shape.fillRule.map { " fillRule=\"\($0)\"" } ?? ""
        for (index, shadow) in shadows.enumerated() {
            let reach = innerShadowReach(shadow)
            let box = shape.domain
            let (mx, my) = (reach / shape.scale.x, reach / shape.scale.y)
            let region = "filterUnits=\"userSpaceOnUse\" x=\"\(svgNumber(box.x - mx))\" y=\"\(svgNumber(box.y - my))\" "
                + "width=\"\(svgNumber(box.width + 2 * mx))\" height=\"\(svgNumber(box.height + 2 * my))\""
            let body = svgInnerShadowFilter(shadow, id: "%@", region: region, scale: shape.scale, composite: .shadowOnly)
            let id = paintID("wc-inner", shape.nodeID, "\(index)|\(shape.geometry)|\(body.joined())")
            defs.append(contentsOf: body.map { $0.replacingOccurrences(of: "%@", with: id) })
            let blend = shadow.blendMode.flatMap { shadow.isBlended ? " style={{ mixBlendMode: \"\(blendModeToCSSValue($0))\" }}" : nil } ?? ""
            copies.append("<\(shape.element) \(shape.geometry) fill=\"black\"\(rule) filter=\"url(#\(id))\"\(blend) />")
        }
        ctx.lines.append(contentsOf: svgDefinitions(defs, pad: pad))
        ctx.lines.append(contentsOf: copies.map { pad + $0 })
    }

    /// The filter ids and definitions that draw an icon's inner shadows over its glyph, one
    /// filter per shadow, bottom first, each applied to what the one before put out.
    ///
    /// - Parameters:
    ///   - shadows: The icon's inner shadows.
    ///   - size: The icon's side, when fixed: the filter region reaches past the box by the
    ///     shadow's offset and blur as a fraction of it; half the box when unknown.
    ///   - nodeID: The node's id, which keeps its filters' ids apart from others'.
    /// - Returns: The `url(#…)` filter functions, in order, and the definitions.
    static func iconInnerShadowFilters(
        _ shadows: [PenEffect.PenShadowEffect], size: Double?, nodeID: String
    ) -> (functions: [String], definitions: [String]) {
        var functions: [String] = []
        var definitions: [String] = []
        for (index, shadow) in shadows.enumerated() {
            let margin = size.map { $0 > 0 ? innerShadowReach(shadow) / $0 : 0.5 } ?? 0.5
            let region = "x=\"\(cssPercent(-margin))\" y=\"\(cssPercent(-margin))\" "
                + "width=\"\(cssPercent(1 + 2 * margin))\" height=\"\(cssPercent(1 + 2 * margin))\""
            let body = svgInnerShadowFilter(shadow, id: "%@", region: region, scale: .identity, composite: .overSource)
            let id = paintID("wc-inner", nodeID, "\(index)|\(body.joined())")
            definitions.append(contentsOf: body.map { $0.replacingOccurrences(of: "%@", with: id) })
            functions.append("url(#\(id))")
        }
        return (functions, definitions)
    }
}
