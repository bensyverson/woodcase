//
//  ReactEmitter+SVGConicPaint.swift
//  Woodcase
//

extension ReactEmitter {
    /// The angular gradient `fill` is, or `nil`: SVG has no paint server for one, so a shape
    /// drawn as SVG paints it as a conic layer (``svgConicLayer(_:shape:overhang:attributes:)``).
    static func angularGradient(_ fill: PenFill) -> PenFill.PenGradientFill? {
        guard case let .gradient(gradient) = fill, gradient.gradientType == .angular else { return nil }
        return gradient
    }

    /// The lines of a `<g>` holding a `foreignObject` that paints an angular gradient over `shape`'s box
    /// grown by `overhang` on every side: a `<div>` whose background is the gradient as a
    /// CSS `conic-gradient` (``cssConicGradient(_:stops:box:outsets:)``), laid out over the
    /// node's box and reaching the overhang, as Pen's paint does.
    ///
    /// `attributes` confine it to what it paints — a clip to the shape for a fill, a mask of
    /// the stroked shape for a stroke — and carry any blend. They sit on a `<g>` around the
    /// object, not on the object: WebKit cuts a masked `foreignObject` off at the SVG's
    /// top-left corner, so a stroke's overhang past the box's top and left went missing
    /// (`render-angular-shapes-path-stroke-outer`, 2026-09-28). In a path's scaling viewBox the
    /// object is in the SVG's user space and is stretched with the shape, so the gradient
    /// keeps Pen's proportions over the node's box.
    ///
    /// - Returns: The lines, unindented, or `nil` for a gradient with no stops.
    static func svgConicLayer(
        _ gradient: PenFill.PenGradientFill,
        shape: SVGStrokedShape,
        overhang: Double,
        attributes: String
    ) -> [String]? {
        let box = FillBox(width: shape.domain.width, height: shape.domain.height)
        let outsets = EdgeLengths(all: SymbolicLength(points: overhang))
        guard let css = cssGradient(gradient, box: box, outsets: outsets) else { return nil }
        let layer = PaintLayer(
            image: css.image, size: css.size, origin: .borderBox, blendMode: PenBlendMode.normal.rawString, position: css.position
        )
        let styles = [("width", "\"100%\""), ("height", "\"100%\"")] + paintLayerDeclarations([layer], withOrigin: false)
        return [
            "<g\(attributes)>",
            "  <foreignObject \(svgRect(shape.domain, grownBy: overhang))>",
            "    <div style={{ \(styles.map { "\($0.0): \($0.1)" }.joined(separator: ", ")) }} />",
            "  </foreignObject>",
            "</g>",
        ]
    }

    /// A `clipPath` of `shape` in `defs`, with the shape's fill rule, and the attribute that
    /// clips an element to it.
    static func svgShapeClip(_ shape: SVGStrokedShape, defs: inout [String]) -> String {
        let id = paintID("wc-clip", shape.nodeID, shape.geometry)
        let rule = shape.fillRule.map { " clipRule=\"\($0)\"" } ?? ""
        if !defs.contains("<clipPath id=\"\(id)\">") {
            defs.append("<clipPath id=\"\(id)\">")
            defs.append("  <\(shape.element) \(shape.geometry)\(rule) />")
            defs.append("</clipPath>")
        }
        return " clipPath=\"url(#\(id))\""
    }

    /// A mask in `defs` that shows what `stroke` covers when `shape` is stroked `width`
    /// wide — white on nothing, with the stroke's cap and join — and the attribute that
    /// masks an element to it: an angular stroke's paint shows through the stroke alone.
    static func svgStrokeMask(
        _ shape: SVGStrokedShape, stroke: any PenStrokable, width: Double, overhang: Double, defs: inout [String]
    ) -> String {
        let outline = "<\(shape.element) \(shape.geometry) fill=\"none\" stroke=\"white\" strokeWidth=\"\(cssNumber(width))\""
            + "\(shape.strokeScaling)\(svgStrokeStyle(stroke)) />"
        let id = paintID("wc-stroke", shape.nodeID, outline)
        if !defs.contains(where: { $0.hasPrefix("<mask id=\"\(id)\"") }) {
            defs.append("<mask id=\"\(id)\" maskUnits=\"userSpaceOnUse\" \(svgRect(shape.domain, grownBy: overhang))>")
            defs.append("  \(outline)")
            defs.append("</mask>")
        }
        return " mask=\"url(#\(id))\""
    }
}
