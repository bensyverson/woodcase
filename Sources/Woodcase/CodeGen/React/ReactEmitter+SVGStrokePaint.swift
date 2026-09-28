//
//  ReactEmitter+SVGStrokePaint.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// A shape an SVG emitter draws, as the stroke painter needs it.
    struct SVGStrokedShape: Friendly {
        /// The SVG element: `path`, `polygon` or `line`.
        var element: String
        /// The element's geometry attributes, e.g. `d="M0 0 L10 10"`.
        var geometry: String
        /// The element's fill attributes (`fill="none"`, with any `fillRule`), or `nil` for
        /// an element that takes no fill.
        var fill: String?
        /// The fill rule, which a clip to the shape must share.
        var fillRule: String?
        /// The node's box in the SVG's user space: the paint's domain.
        var domain: Box
        /// The node's id, which keeps the ids of its paint servers apart from other nodes'.
        var nodeID: String
        /// Points per user unit on each axis: how the SVG's viewBox scales its user space
        /// onto the node's box.
        var scale = Scale.identity

        /// Whether the SVG's viewBox scales its user space onto the node's box, so a stroke
        /// drawn in it would scale too; the renderer strokes the mapped outline at the
        /// stroke's own width, so such a stroke is written non-scaling.
        var viewBoxScales: Bool {
            scale != .identity
        }

        /// The stroke attributes that keep a stroke at its own width under a scaling viewBox.
        var strokeScaling: String {
            viewBoxScales ? " vectorEffect=\"non-scaling-stroke\"" : ""
        }

        /// A scale on each axis.
        struct Scale: Friendly {
            /// Points per user unit along x.
            var x: Double
            /// Points per user unit along y.
            var y: Double

            /// No scaling: one point per unit.
            static let identity = Scale(x: 1, y: 1)
        }

        /// A rectangle as four numbers, which keeps the emitter free of CoreGraphics.
        struct Box: Friendly {
            /// The left edge.
            var x: Double
            /// The top edge.
            var y: Double
            /// The width.
            var width: Double
            /// The height.
            var height: Double
        }
    }

    /// Writes the children of an SVG that strokes `shape` with every layer of `fills`.
    ///
    /// Each layer is a paint server in `userSpaceOnUse` over the node's box — a linear or
    /// radial gradient in Pen's exact geometry, or a pattern holding an image
    /// or mesh raster once, with room around it so it is not tiled into the stroke's
    /// overhang — and each is one stroked copy of the shape, bottom first. An inner stroke
    /// is drawn at twice the width and clipped to the shape; an outer one twice the width,
    /// masked by the shape; Pen's own export draws them the same way. The fill is drawn
    /// once, beneath the strokes. An angular gradient, which has no SVG paint server, is a
    /// conic layer masked by the stroked shape (``svgConicLayer(_:shape:overhang:attributes:)``);
    /// a themed mesh has no single image, so it is left out.
    static func emitPaintedSVGShape(
        _ shape: SVGStrokedShape,
        fills: [PenFill],
        stroke: any PenStrokable,
        indent: Int,
        ctx: EmitContext
    ) {
        let pad = String(repeating: " ", count: indent)
        let width = stroke.uniformStrokeWidth ?? 1
        let alignment: PenStrokeAlign = shape.fill == nil ? .center : stroke.strokeAlignment ?? .center
        let drawnWidth = alignment == .center ? width : width * 2
        let overhang = drawnWidth * 2 + 1

        var defs: [String] = []
        var layers: [StrokeLayer] = []
        for (index, fill) in fills.enumerated() {
            let blend = fill.blendMode.flatMap { $0 == .normal ? nil : blendModeToCSSValue($0) }
            if let gradient = angularGradient(fill) {
                layers.append(StrokeLayer(paint: .conic(gradient), blend: blend))
            } else if let paint = svgPaint(fill, index: index, shape: shape, overhang: overhang, defs: &defs, ctx: ctx) {
                layers.append(StrokeLayer(paint: .server(paint), blend: blend))
            }
        }

        var strokeClip = ""
        switch alignment {
        case .center:
            break
        case .inner:
            strokeClip = svgShapeClip(shape, defs: &defs)
        case .outer:
            let id = paintID("wc-mask", shape.nodeID, shape.geometry)
            let region = svgRect(shape.domain, grownBy: overhang)
            let rule = shape.fillRule.map { " fillRule=\"\($0)\"" } ?? ""
            defs.append("<mask id=\"\(id)\" maskUnits=\"userSpaceOnUse\" \(region)>")
            defs.append("  <rect \(region) fill=\"white\" />")
            defs.append("  <\(shape.element) \(shape.geometry) fill=\"black\"\(rule) />")
            defs.append("</mask>")
            strokeClip = " mask=\"url(#\(id))\""
        }

        if !defs.isEmpty {
            ctx.lines.append("\(pad)<defs>")
            ctx.lines.append(contentsOf: defs.map { "\(pad)  \($0)" })
            ctx.lines.append("\(pad)</defs>")
        }

        // The fill rides on the first stroke when nothing about that stroke would also
        // change the fill (a clip, a mask, a blend mode, a conic layer).
        let fillSeparately = alignment != .center || layers.first?.blend != nil || layers.first?.isServer != true
        if fillSeparately, let fill = shape.fill, !fill.hasPrefix("fill=\"none\"") {
            ctx.lines.append("\(pad)<\(shape.element) \(shape.geometry) \(fill) />")
        }
        var conicMask: String?
        for (index, layer) in layers.enumerated() {
            let blend = layer.blend.map { " style={{ mixBlendMode: \"\($0)\" }}" } ?? ""
            switch layer.paint {
            case let .server(paint):
                let fill: String = if let fill = shape.fill {
                    index == 0 && !fillSeparately ? " \(fill)" : " fill=\"none\""
                } else {
                    ""
                }
                let strokeAttributes = "stroke=\"\(paint)\" strokeWidth=\"\(cssNumber(drawnWidth))\"\(shape.strokeScaling)\(svgStrokeStyle(stroke))"
                ctx.lines.append("\(pad)<\(shape.element) \(shape.geometry)\(fill) \(strokeAttributes)\(strokeClip)\(blend) />")
            case let .conic(gradient):
                // Every conic layer is masked by the same stroked shape: define it once.
                let mask: String
                if let conicMask {
                    mask = conicMask
                } else {
                    var maskDefs: [String] = []
                    mask = svgStrokeMask(shape, stroke: stroke, width: drawnWidth, overhang: overhang, defs: &maskDefs)
                    ctx.lines.append(contentsOf: svgDefinitions(maskDefs, pad: pad))
                    conicMask = mask
                }
                guard let conic = svgConicLayer(gradient, shape: shape, overhang: overhang, attributes: mask + blend) else { continue }
                if strokeClip.isEmpty {
                    ctx.lines.append(contentsOf: conic.map { "\(pad)\($0)" })
                } else {
                    ctx.lines.append("\(pad)<g\(strokeClip)>")
                    ctx.lines.append(contentsOf: conic.map { "\(pad)  \($0)" })
                    ctx.lines.append("\(pad)</g>")
                }
            }
        }
    }

    /// `definitions` as a `<defs>` block at `pad`, or nothing when there are none.
    static func svgDefinitions(_ definitions: [String], pad: String) -> [String] {
        guard !definitions.isEmpty else { return [] }
        return ["\(pad)<defs>"] + definitions.map { "\(pad)  \($0)" } + ["\(pad)</defs>"]
    }

    /// A stroke's cap and join as SVG attributes, each written only when it is not SVG's
    /// default (butt, miter), which is Pen's default too — e.g. ` strokeLinecap="round"`.
    static func svgStrokeStyle(_ stroke: any PenStrokable) -> String {
        var attributes = ""
        if let cap = stroke.strokeLinecap, cap != .butt {
            attributes += " strokeLinecap=\"\(cap.rawValue)\""
        }
        if let join = stroke.strokeLinejoin, join != .miter {
            attributes += " strokeLinejoin=\"\(join.rawValue)\""
        }
        return attributes
    }

    /// The `stroke` (or `fill`) value for one layer — a colour, or `url(#…)` of a paint
    /// server written into `defs` — or `nil` for a layer SVG cannot paint: an angular
    /// gradient, a themed mesh, an image without a URL, a shader. An icon's glyph is painted
    /// by the same servers (``iconPaint(_:family:nodeID:ctx:)``), with no overhang.
    static func svgPaint(
        _ fill: PenFill,
        index: Int,
        shape: SVGStrokedShape,
        overhang: Double,
        defs: inout [String],
        ctx: EmitContext
    ) -> String? {
        let box = shape.domain
        switch fill {
        case .shorthand, .color:
            return emitFillValueRaw(fill)
        case let .gradient(gradient):
            guard let stops = gradientStops(gradient) else { return nil }
            let transform = "gradientTransform=\"\(svgGradientMatrix(gradient, box: box))\""
            let open: String
            let close: String
            switch gradient.gradientType {
            case .linear, nil:
                open = "<linearGradient id=\"%@\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0.5\" x2=\"0\" y2=\"-0.5\" \(transform)>"
                close = "</linearGradient>"
            case .radial:
                open = "<radialGradient id=\"%@\" gradientUnits=\"userSpaceOnUse\" cx=\"0\" cy=\"0\" r=\"0.5\" \(transform)>"
                close = "</radialGradient>"
            case .angular:
                return nil
            }
            let stopLines = stops.map { "  <stop offset=\"\(cssNumber($0.position))\" style={{ stopColor: \"\($0.color)\" }} />" }
            let id = paintID("wc-paint", shape.nodeID, "\(index)|\(open)|\(stopLines.joined())")
            defs.append(open.replacingOccurrences(of: "%@", with: id))
            defs.append(contentsOf: stopLines)
            defs.append(close)
            return "url(#\(id))"
        case let .image(image):
            guard let url = image.url else { return nil }
            let fit = switch image.mode {
            case .stretch: "none"
            case .fit: "xMidYMid meet"
            case .fill, nil: "xMidYMid slice"
            }
            return svgPattern(url: url, preserveAspectRatio: fit, index: index, shape: shape, overhang: overhang, defs: &defs)
        case let .meshGradient(mesh):
            let box = FillBox(width: shape.domain.width, height: shape.domain.height)
            guard let image = emitMeshImage(mesh, box: box, ctx: ctx),
                  let url = image.firstMatch(of: /^url\('(.*)'\)$/)?.output.1
            else { return nil }
            return svgPattern(url: String(url), preserveAspectRatio: "none", index: index, shape: shape, overhang: overhang, defs: &defs)
        case .shader, .unknown:
            return nil
        }
    }

    /// A pattern that draws `url` once over the node's box, inside a tile `overhang` larger
    /// on every side so the stroke's overhang past the box shows nothing rather than a
    /// repeat — Pen draws an image paint only where the placed image is.
    private static func svgPattern(
        url: String,
        preserveAspectRatio: String,
        index: Int,
        shape: SVGStrokedShape,
        overhang: Double,
        defs: inout [String]
    ) -> String {
        let box = shape.domain
        let image = "<image href=\"\(url)\" x=\"\(svgNumber(overhang))\" y=\"\(svgNumber(overhang))\" "
            + "width=\"\(svgNumber(box.width))\" height=\"\(svgNumber(box.height))\" preserveAspectRatio=\"\(preserveAspectRatio)\" />"
        let id = paintID("wc-paint", shape.nodeID, "\(index)|\(image)")
        defs.append("<pattern id=\"\(id)\" patternUnits=\"userSpaceOnUse\" \(svgRect(box, grownBy: overhang))>")
        defs.append("  \(image)")
        defs.append("</pattern>")
        return "url(#\(id))"
    }

    /// The SVG `matrix(…)` from a gradient's own unit space onto the node's box: Pen's map
    /// into the normalised box (``GradientGeometry/affineComponents``), the one the renderer's
    /// `frameTransform(in:)` uses, then stretched to the box — so a turned gradient on a box
    /// that is not square keeps Pen's slant.
    private static func svgGradientMatrix(_ gradient: PenFill.PenGradientFill, box: SVGStrokedShape.Box) -> String {
        let m = GradientGeometry(gradient).affineComponents
        let values = [
            box.width * m.a,
            box.height * m.b,
            box.width * m.c,
            box.height * m.d,
            box.x + box.width * m.tx,
            box.y + box.height * m.ty,
        ]
        return "matrix(\(values.map { svgNumber($0) }.joined(separator: " ")))"
    }

    /// `x`, `y`, `width` and `height` attributes of `box` grown by `margin` on every side.
    static func svgRect(_ box: SVGStrokedShape.Box, grownBy margin: Double) -> String {
        "x=\"\(svgNumber(box.x - margin))\" y=\"\(svgNumber(box.y - margin))\" "
            + "width=\"\(svgNumber(box.width + margin * 2))\" height=\"\(svgNumber(box.height + margin * 2))\""
    }

    /// A deterministic id for a definition: `prefix-` and twelve hex digits of a hash of the
    /// node's id and the definition itself, so repeated emissions agree and two instances
    /// of one component share one identical definition.
    static func paintID(_ prefix: String, _ nodeID: String, _ content: String) -> String {
        var hasher = FNV1aHasher()
        hasher.combine(nodeID)
        hasher.combine("|")
        hasher.combine(content)
        return "\(prefix)-\(hasher.hexString.prefix(12))"
    }

    /// An SVG coordinate: at most three decimals.
    static func svgNumber(_ value: Double) -> String {
        cssNumber(value, decimals: 3)
    }
}
