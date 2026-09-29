//
//  ReactEmitter+SVGFillPaint.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// The `fill` attributes of a shape drawn as SVG when its fills are one plain color:
    /// `fill="#hex"`, with the fill rule when there is one — or `fill="none"` when the fills
    /// are drawn as layers (``emitSVGFillLayers(_:fills:indent:ctx:)``) under it.
    static func svgFillAttributes(_ fills: PenFills?, fillRule: String? = nil) -> String {
        guard PaintRoute(fills).layeredFills == nil else { return "fill=\"none\"" }
        return "fill=\"\(svgFillColor(fills))\"" + (fillRule.map { " fillRule=\"\($0)\"" } ?? "")
    }

    /// Writes an SVG shape's elements: its fill layers when one color cannot carry its
    /// fills, then its inner shadows (``emitSVGInnerShadows(_:shadows:indent:ctx:)``), then
    /// its stroke — painted layers (``emitPaintedSVGShape(_:fills:stroke:indent:ctx:)``),
    /// which a plain color placed inside or outside the outline takes too, or one element
    /// with a plain `stroke` — or, for plain fills and a centered plain stroke and no inner
    /// shadow between them, one element carrying both.
    ///
    /// - Parameters:
    ///   - shape: The shape, its `fill` from ``svgFillAttributes(_:fillRule:)``.
    ///   - fills: The node's fills.
    ///   - stroke: The node's stroke keys, as ``PenStrokable/drawn(on:)`` gives them.
    ///   - innerShadows: The node's enabled inner shadows, bottom first.
    ///   - indent: The indentation of the written lines.
    ///   - ctx: The emit context the lines are appended to.
    static func emitSVGShape(
        _ shape: SVGStrokedShape,
        fills: PenFills?,
        stroke: any PenStrokable,
        innerShadows: [PenEffect.PenShadowEffect] = [],
        indent: Int,
        ctx: EmitContext
    ) {
        var shape = shape
        let fillLayers = PaintRoute(fills).layeredFills
        if let fillLayers {
            emitSVGFillLayers(shape, fills: fillLayers, indent: indent, ctx: ctx)
        }
        let strokeRoute = PaintRoute(stroke.stroke)
        let paintedStroke = strokeRoute.layeredFills ?? alignedSolid(strokeRoute, stroke: stroke, shape: shape)
        let strokeColor = strokeRoute.plainColor.map(cssColorReference)
        if !innerShadows.isEmpty {
            // The fill goes down on its own, so the shadows land between it and the stroke.
            if fillLayers == nil, let fill = shape.fill, !fill.hasPrefix("fill=\"none\"") {
                ctx.lines.append("\(String(repeating: " ", count: indent))<\(shape.element) \(shape.geometry) \(fill) />")
            }
            emitSVGInnerShadows(shape, shadows: innerShadows, indent: indent, ctx: ctx)
            guard paintedStroke != nil || strokeColor != nil else { return }
            shape.fill = shape.fill.map { _ in "fill=\"none\"" }
        }
        if let paintedStroke {
            emitPaintedSVGShape(shape, fills: paintedStroke, stroke: stroke, indent: indent, ctx: ctx)
            return
        }
        guard fillLayers == nil || strokeColor != nil else { return }
        var attrs = "\(shape.geometry) \(shape.fill ?? "fill=\"none\"")"
        if let strokeColor { attrs += " stroke=\"\(strokeColor)\"" }
        if case let .uniform(width) = stroke.strokeWidth, let width = width.literalValue {
            attrs += " strokeWidth=\"\(cssNumber(width))\""
        }
        if strokeColor != nil { attrs += shape.strokeScaling + svgStrokeStyle(stroke) }
        ctx.lines.append("\(String(repeating: " ", count: indent))<\(shape.element) \(attrs) />")
    }

    /// Whether an SVG shape's stroke can reach past the node's box, which the SVG must then
    /// draw outside its viewport: any stroke with an enabled paint.
    static func svgStrokeOverflows(_ stroke: any PenStrokable) -> Bool {
        PaintRoute(stroke.stroke) != .none
    }

    /// A plain-color stroke placed inside or outside the outline, as one paint layer for
    /// ``emitPaintedSVGShape(_:fills:stroke:indent:ctx:)``, which honors the alignment an
    /// SVG `stroke` attribute cannot; `nil` for a centered stroke, another route, or a shape
    /// that takes no fill (a line, whose stroke Pen always centers).
    private static func alignedSolid(_ route: PaintRoute, stroke: any PenStrokable, shape: SVGStrokedShape) -> [PenFill]? {
        guard let color = route.plainColor, shape.fill != nil, (stroke.strokeAlignment ?? .center) != .center else {
            return nil
        }
        return [.color(PenFill.PenColorFill(color: color))]
    }

    /// Writes the fills of an SVG shape that one `fill` color cannot carry — a gradient,
    /// an image, a mesh, a stack, a blended color — as one filled copy of the shape per
    /// layer, bottom first, each painted by ``svgPaint(_:index:shape:overhang:defs:ctx:)``
    /// over the node's box, which is Pen's paint domain for a fill as for a stroke. An
    /// angular gradient, which SVG has no paint server for, is a conic layer clipped to the
    /// shape (``svgConicLayer(_:shape:overhang:attributes:)``); a layer nothing can paint
    /// (a themed mesh, a shader) is left out. The strokes are drawn after, over these.
    ///
    /// - Parameters:
    ///   - shape: The shape; its `fillRule` is each copy's.
    ///   - fills: The enabled fills, bottom to top (``PaintRoute/layeredFills``).
    ///   - indent: The indentation of the written lines.
    ///   - ctx: The emit context the lines are appended to.
    static func emitSVGFillLayers(_ shape: SVGStrokedShape, fills: [PenFill], indent: Int, ctx: EmitContext) {
        let pad = String(repeating: " ", count: indent)
        // A pattern tile this much larger than the box keeps an image from repeating
        // under geometry that reaches past the box, as a path's may.
        let overhang = max(shape.domain.width, shape.domain.height)
        var defs: [String] = []
        var layers: [String] = []
        for (index, fill) in fills.enumerated() {
            let blend = fill.blendMode.flatMap { $0 == .normal ? nil : blendModeToCSSValue($0) }
                .map { " style={{ mixBlendMode: \"\($0)\" }}" } ?? ""
            if let gradient = angularGradient(fill) {
                let clip = svgShapeClip(shape, defs: &defs)
                layers += svgConicLayer(gradient, shape: shape, overhang: overhang, attributes: clip + blend) ?? []
                continue
            }
            guard let paint = svgPaint(fill, index: index, shape: shape, overhang: overhang, defs: &defs, ctx: ctx) else {
                continue
            }
            let rule = shape.fillRule.map { " fillRule=\"\($0)\"" } ?? ""
            layers.append("<\(shape.element) \(shape.geometry) fill=\"\(paint)\"\(rule)\(blend) />")
        }
        if !defs.isEmpty {
            ctx.lines.append("\(pad)<defs>")
            ctx.lines.append(contentsOf: defs.map { "\(pad)  \($0)" })
            ctx.lines.append("\(pad)</defs>")
        }
        ctx.lines.append(contentsOf: layers.map { "\(pad)\($0)" })
    }
}
