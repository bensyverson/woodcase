//
//  ReactEmitter+PaintLayer.swift
//  Woodcase
//

extension ReactEmitter {
    /// One fill as a CSS background layer on an element that shows the paint somewhere
    /// other than its own background: text glyphs, or a stroke overlay.
    struct PaintLayer: Friendly {
        /// Which of the element's boxes a layer is sized and placed against.
        enum Origin: String, Friendly {
            /// The whole element: a flat colour, or a gradient whose geometry has already
            /// been pulled back onto the node's box (``ReactEmitter/cssGradient(_:box:outsets:)``).
            case borderBox = "border-box"
            /// The node's box: an image or a mesh raster, drawn there and nowhere else, as
            /// Pen draws an image paint (finding 2 of the fills report: images are decal).
            case paddingBox = "padding-box"
        }

        /// The `background-image` value.
        var image: String

        /// The `background-size` value.
        var size: String

        /// The box the layer is laid out against.
        var origin: Origin

        /// The CSS blend mode against the layers beneath it.
        var blendMode: String

        /// The `background-position` value: centred, unless a gradient's tile sits off
        /// the element's centre (``ReactEmitter/tilePosition(outsets:)``).
        var position: String = CSSGradient.centered

        /// The size of a layer that fills its box.
        static let fullSize = "100% 100%"
    }

    /// Every fill that CSS can paint as a layer, **top first** (the order CSS stacks
    /// background layers in), each laid out over the node's box.
    ///
    /// - Parameters:
    ///   - fills: The enabled fills, bottom to top, as .pen lists them.
    ///   - outsets: How far the painted element reaches past the node's box on each side —
    ///     zero for text, the stroke's outer reach for a stroke overlay.
    ///   - box: The node's box, which sizes a mesh raster and gives a gradient its proportions.
    ///   - ctx: The emission context, for a themed mesh.
    /// - Returns: The layers; a shader, an unknown fill or an image without a URL has none.
    static func paintLayers(
        _ fills: [PenFill],
        outsets: EdgeLengths,
        box: FillBox,
        ctx: EmitContext
    ) -> [PaintLayer] {
        fills.reversed().compactMap { fill -> PaintLayer? in
            let blend = fill.blendMode.map(blendModeToCSSValue) ?? PenBlendMode.normal.rawString
            switch fill {
            case .shorthand, .color:
                guard let color = emitFillValueRaw(fill) else { return nil }
                return PaintLayer(
                    image: "linear-gradient(\(color), \(color))",
                    size: PaintLayer.fullSize,
                    origin: .borderBox,
                    blendMode: blend
                )
            case let .gradient(gradient):
                guard let css = cssGradient(gradient, box: box, outsets: outsets) else { return nil }
                return PaintLayer(image: css.image, size: css.size, origin: .borderBox, blendMode: blend, position: css.position)
            case let .image(image):
                guard let url = image.url else { return nil }
                return PaintLayer(image: "url('\(url)')", size: cssImageSize(image.mode), origin: .paddingBox, blendMode: blend)
            case let .meshGradient(mesh):
                guard let css = emitMeshImage(mesh, box: box, ctx: ctx) else { return nil }
                return PaintLayer(image: css, size: PaintLayer.fullSize, origin: .paddingBox, blendMode: blend)
            case .shader, .unknown:
                return nil
            }
        }
    }

    /// The `background-size` that places an image fill over its box the way its mode does.
    static func cssImageSize(_ mode: PenImageFillMode?) -> String {
        switch mode {
        case .fill, nil: "cover"
        case .fit: "contain"
        case .stretch: PaintLayer.fullSize
        }
    }

    /// The background declarations that draw `layers`, in `style` order.
    ///
    /// - Parameters:
    ///   - layers: The layers, top first.
    ///   - withOrigin: Whether to state each layer's `background-origin` — needed where the
    ///     element's border and padding boxes differ from the node's box.
    static func paintLayerDeclarations(_ layers: [PaintLayer], withOrigin: Bool) -> [(String, String)] {
        let sizes = layers.map(\.size)
        let positions = layers.map(\.position)
        var declarations: [(String, String)] = [
            ("backgroundImage", "\"\(layers.map(\.image).joined(separator: ", "))\""),
            ("backgroundSize", "\"\(Set(sizes).count == 1 ? sizes[0] : sizes.joined(separator: ", "))\""),
            ("backgroundPosition", "\"\(Set(positions).count == 1 ? positions[0] : positions.joined(separator: ", "))\""),
            ("backgroundRepeat", "\"no-repeat\""),
        ]
        if withOrigin {
            declarations.append(("backgroundOrigin", "\"\(layers.map(\.origin.rawValue).joined(separator: ", "))\""))
        }
        let normal = PenBlendMode.normal.rawString
        if layers.count > 1, layers.contains(where: { $0.blendMode != normal }) {
            declarations.append(("backgroundBlendMode", "\"\(layers.map(\.blendMode).joined(separator: ", "))\""))
        }
        return declarations
    }

    /// The `mix-blend-mode` a lone layer needs, which `background-blend-mode` cannot give it:
    /// that blends a layer only with the layers beneath it on the same element.
    static func loneLayerBlend(_ layers: [PaintLayer]) -> String? {
        guard layers.count == 1, layers[0].blendMode != PenBlendMode.normal.rawString else { return nil }
        return layers[0].blendMode
    }
}
