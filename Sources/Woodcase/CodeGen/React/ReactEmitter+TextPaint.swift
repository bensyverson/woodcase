//
//  ReactEmitter+TextPaint.swift
//  Woodcase
//

extension ReactEmitter {
    /// The declarations that paint a text node's glyphs.
    ///
    /// A lone solid colour is `color`, as it always was. Anything more is painted the way
    /// Pen paints it (`project/2026-09-26-text-and-stroke-fills.md`, findings 1 and 6):
    /// every enabled fill is a background layer laid out over the text's own box, top fill
    /// first, shown only through the glyphs by `background-clip: text` with the glyph fill
    /// made transparent. A stack keeps each layer's blend mode as `background-blend-mode`;
    /// a lone blended fill blends the element. Auto-width text is sized to its content so
    /// that the box the paint spans is the text's, not its container's.
    ///
    /// No enabled paint — or only paint the emitter cannot draw, a shader — writes a
    /// transparent colour, since an element with none inherits the page's black and Pen
    /// draws such a text as nothing. A solid is written by ``glyphColor(_:)``.
    ///
    /// - Parameters:
    ///   - data: The text node.
    ///   - nodeBlendMode: The node's own blend mode, which a fill's blend mode must not
    ///     overwrite: both would be `mix-blend-mode`.
    ///   - ctx: The emission context, for a themed mesh.
    static func textPaintStyles(
        _ data: PenNode.TextData,
        nodeBlendMode: PenBlendMode?,
        ctx: EmitContext
    ) -> [(String, String)] {
        let elementBlendFree = nodeBlendMode.map { $0 == .normal } ?? true
        switch PaintRoute(data.fills) {
        case .none:
            return [("color", "\"\(noGlyphPaint)\"")]
        case let .solid(color, blendMode):
            var styles = [("color", "\"\(glyphColor(color))\"")]
            if elementBlendFree, let blendMode, blendMode != .normal {
                styles.append(("mixBlendMode", "\"\(blendModeToCSSValue(blendMode))\""))
            }
            return styles
        case let .painted(fills):
            let layers = paintLayers(
                fills, outsets: EdgeLengths(all: .zero), box: FillBox(width: data.width, height: data.height), ctx: ctx
            )
            guard !layers.isEmpty else { return [("color", "\"\(noGlyphPaint)\"")] }
            var styles = paintLayerDeclarations(layers, withOrigin: false)
            styles.append(contentsOf: [
                ("backgroundClip", "\"text\""),
                ("WebkitBackgroundClip", "\"text\""),
                ("WebkitTextFillColor", "\"transparent\""),
                ("color", "\"transparent\""),
            ])
            if elementBlendFree, let blend = loneLayerBlend(layers) {
                styles.append(("mixBlendMode", "\"\(blend)\""))
            }
            if (data.textGrowth ?? .auto) == .auto {
                styles.append(("width", "\"fit-content\""))
            }
            return styles
        }
    }

    /// The CSS colour that draws a text's or an icon's glyphs as nothing.
    static let noGlyphPaint = "transparent"

    /// The CSS colour for glyphs painted `color`: a literal as written, a variable as its
    /// custom property — except a literal that is not a colour, which Pen paints black and
    /// so is `#000000` (CSS would drop it and inherit, and an SVG `stroke` would draw
    /// nothing).
    static func glyphColor(_ color: PenValue<String>) -> String {
        if case let .literal(value) = color, PenHexColor(value) == nil {
            return "#000000"
        }
        return cssColorReference(color)
    }

    /// The one CSS colour for glyphs painted `fills`, where only a colour can be written (a
    /// state's colour; an icon paints more, by ``iconPaint(_:family:nodeID:ctx:)``):
    /// ``noGlyphPaint`` when nothing is enabled, else the topmost enabled solid by
    /// `glyphColor(_:)`. `nil` when every enabled fill is paint a colour cannot carry (a
    /// gradient, an image).
    static func glyphColor(_ fills: PenFills?) -> String? {
        let enabled = fills?.all.filter(\.isEnabled) ?? []
        guard !enabled.isEmpty else { return noGlyphPaint }
        return enabled.last { $0.solidColor != nil }?.solidColor.map(glyphColor)
    }
}
