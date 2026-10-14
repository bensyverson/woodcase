//
//  SVGWriter+Stroke.swift
//  Woodcase
//

import CoreGraphics

extension SVGWriter {
    /// A node's stroke, as ``PenStrokeRenderer/renderStroke(_:path:rect:roundedBox:in:imageProvider:)``
    /// draws it.
    ///
    /// A uniform stroke stays an SVG stroke, so an editor can still change its width: a
    /// centered one at its own width; an inner or outer one at twice its width, cut by a
    /// clip to the shape or a mask of its complement — the CG renderer's own construction.
    /// Its solid colors and gradients are stroke paints; an image, angular or mesh paint
    /// fills the stroke's outline instead. A per-side stroke and a zero-area box's band,
    /// which SVG's stroke model cannot say, are their ring filled even-odd.
    ///
    /// - Parameters:
    ///   - strokable: The node's stroke keys, per-side widths already made uniform where the
    ///     shape has no sides.
    ///   - path: The node's outline.
    ///   - box: The paint's domain: the node's box, or a line's band.
    ///   - roundedBox: The node's box and radii when it is box-shaped.
    /// - Returns: The stroke's elements, one per paint.
    func stroke(
        _ strokable: (any PenStrokable)?,
        path: CGPath,
        box: PenRect,
        roundedBox: PenStrokeRenderer.RoundedBox?
    ) -> [SVGElement] {
        guard let strokable, let fills = strokable.stroke else { return [] }
        let domain = box.cgRect
        let alignment = strokable.strokeAlignment ?? .center

        if case let .perSide(sides) = strokable.strokeWidth, let roundedBox {
            let widths = PenStrokeRenderer.SideWidths(sides)
            guard !widths.isEmpty else { return [] }
            let ring = PenStrokeRenderer.perSideRing(widths: widths, alignment: alignment, box: roundedBox)
            return paint(fills, through: SVGShape(path: ring, rule: .evenOdd), domain: domain)
        }
        guard let width = strokable.uniformStrokeWidth.map({ CGFloat($0) }), width > 0 else { return [] }
        let style = PenStrokeRenderer.Style(
            width: width, alignment: alignment, penJoin: strokable.strokeLinejoin, penCap: strokable.strokeLinecap
        )
        if let band = PenStrokeRenderer.zeroAreaBand(width: width, alignment: alignment, box: roundedBox) {
            return paint(fills, through: SVGShape(path: band, rule: .evenOdd), domain: domain)
        }

        let cut = alignmentCut(style, path: path)
        let d = path.svgPathData
        return fills.all.flatMap { fill -> [SVGElement] in
            var layers: [SVGElement]
            if let paint = strokePaint(fill, domain: domain) {
                var element = SVGElement("path", ["d": d, "fill": "none", "stroke": paint.value])
                element["stroke-opacity"] = paint.opacity
                element["stroke-width"] = Double(style.outlineWidth).svgNumber
                element["stroke-linejoin"] = style.penJoin.map(\.rawValue)
                element["stroke-linecap"] = style.penCap.map(\.rawValue)
                if style.join == .miter {
                    element["stroke-miterlimit"] = Double(PenStrokeRenderer.Style.miterLimit).svgNumber
                }
                element["style"] = paint.blend?.svgStyle
                layers = [element]
            } else {
                let outline = path.copy(
                    strokingWithWidth: style.outlineWidth, lineCap: style.cap, lineJoin: style.join,
                    miterLimit: PenStrokeRenderer.Style.miterLimit
                )
                layers = self.paint(.single(fill), through: SVGShape(path: outline, rule: .winding), domain: domain)
            }
            if let cut {
                layers = layers.map { layer in
                    var cutLayer = layer
                    cutLayer[cut.attribute] = cut.url
                    return cutLayer
                }
            }
            return layers
        }
    }

    /// A paint SVG can stroke with: its `stroke` value, its alpha and its blend mode.
    private struct StrokePaint {
        /// A color or `url(#…)`.
        let value: String
        /// The `stroke-opacity`, or `nil` for opaque.
        let opacity: String?
        /// The paint's blend mode.
        let blend: PenBlendMode?
    }

    /// `fill` as a stroke paint, or `nil` when it must fill the stroke's outline instead —
    /// an image, angular or mesh paint — or draws nothing.
    private func strokePaint(_ fill: PenFill, domain: CGRect) -> StrokePaint? {
        switch fill {
        case let .shorthand(hex):
            return PenHexColor(hex).map { StrokePaint(value: $0.svgColor, opacity: $0.alpha == 255 ? nil : $0.svgAlpha, blend: nil) }
        case let .color(color):
            guard color.enabled?.literalValue != false,
                  let hex = color.color.literalValue.flatMap(PenHexColor.init)
            else { return nil }
            return StrokePaint(value: hex.svgColor, opacity: hex.alpha == 255 ? nil : hex.svgAlpha, blend: color.blendMode)
        case let .gradient(gradient) where gradient.gradientType != .angular && gradient.enabled?.literalValue != false:
            guard let url = gradientDefinition(gradient, domain: domain) else { return nil }
            let opacity = gradient.opacity?.literalValue.flatMap { $0 < 1 ? max(0, $0).svgOpacity : nil }
            return StrokePaint(value: url, opacity: opacity, blend: gradient.blendMode)
        default:
            return nil
        }
    }

    /// The clip or mask that cuts a doubled-width stroke to its alignment, or `nil` for a
    /// centered stroke.
    private func alignmentCut(_ style: PenStrokeRenderer.Style, path: CGPath) -> (attribute: String, url: String)? {
        switch style.alignment {
        case .center:
            return nil
        case .inner:
            let clip = SVGElement("clipPath", children: [SVGElement("path", ["d": path.svgPathData])])
            return ("clip-path", define(clip, prefix: "clip"))
        case .outer:
            let outline = path.copy(
                strokingWithWidth: style.outlineWidth, lineCap: style.cap, lineJoin: style.join,
                miterLimit: PenStrokeRenderer.Style.miterLimit
            )
            let reach = style.solidOuterBounds(of: path).union(outline.boundingBox).insetBy(dx: -1, dy: -1)
            let mask = SVGElement("mask", [
                "maskUnits": "userSpaceOnUse",
                "x": Double(reach.minX).svgNumber, "y": Double(reach.minY).svgNumber,
                "width": Double(reach.width).svgNumber, "height": Double(reach.height).svgNumber,
            ], children: [
                SVGElement("rect", [
                    "x": Double(reach.minX).svgNumber, "y": Double(reach.minY).svgNumber,
                    "width": Double(reach.width).svgNumber, "height": Double(reach.height).svgNumber,
                    "fill": "#ffffff",
                ]),
                SVGElement("path", ["d": path.svgPathData, "fill": "#000000"]),
            ])
            return ("mask", define(mask, prefix: "mask"))
        }
    }
}
