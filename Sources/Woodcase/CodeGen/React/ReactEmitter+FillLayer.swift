//
//  ReactEmitter+FillLayer.swift
//  Woodcase
//

extension ReactEmitter {
    /// One element drawn over a box's background: a paint the background cannot draw, the
    /// inner strokes and shadows that must stay over such a paint, or a stroke overlay that
    /// holds such paints. An absolutely positioned `<div aria-hidden="true">` with
    /// `declarations`, holding `content`, then `children`.
    struct FillLayer: Friendly {
        /// One CSS declaration in a `style` object.
        struct Declaration: Friendly {
            /// The camel-cased property.
            var property: String
            /// The value, as JSX writes it.
            var value: String
        }

        /// The element's style.
        var declarations: [Declaration]
        /// The element it holds first, if any: an ``ReactEmitter/imageCropElement(_:href:frame:ctx:)``.
        var content: String?
        /// The layers it holds after `content`, bottom first: a stroke overlay's paints.
        var children: [FillLayer]

        /// A layer with `styles` holding `content`, then `children`.
        init(_ styles: [(String, String)], content: String? = nil, children: [FillLayer] = []) {
            declarations = styles.map { Declaration(property: $0.0, value: $0.1) }
            self.content = content
            self.children = children
        }

        /// The style as the `(property, value)` pairs the emitter writes.
        var styles: [(String, String)] {
            declarations.map { ($0.property, $0.value) }
        }
    }

    /// Writes each layer as a hidden `<div>`, bottom first.
    static func emitFillLayers(_ layers: [FillLayer], indent: Int, ctx: EmitContext) {
        for layer in layers {
            emitLayer(layer, indent: indent, ctx: ctx)
        }
    }

    /// Writes `layer` as a hidden `<div>`: self-closing when it holds nothing.
    static func emitLayer(_ layer: FillLayer, indent: Int, ctx: EmitContext) {
        guard layer.content != nil || !layer.children.isEmpty else {
            emitStrokeOverlay(layer.styles, indent: indent, ctx: ctx)
            return
        }
        let pad = String(repeating: " ", count: indent)
        ctx.lines.append("\(pad)<div")
        ctx.lines.append("\(pad)  aria-hidden=\"true\"")
        ctx.lines.append("\(pad)  style={{")
        for (key, value) in layer.styles {
            ctx.lines.append("\(pad)    \(key): \(value),")
        }
        ctx.lines.append("\(pad)  }}")
        ctx.lines.append("\(pad)>")
        if let content = layer.content {
            ctx.lines.append("\(pad)  \(content)")
        }
        emitFillLayers(layer.children, indent: indent + 2, ctx: ctx)
        ctx.lines.append("\(pad)</div>")
    }
}
