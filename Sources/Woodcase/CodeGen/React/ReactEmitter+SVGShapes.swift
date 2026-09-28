//
//  ReactEmitter+SVGShapes.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    // MARK: - Polygon

    /// Emits a regular polygon as an SVG `<polygon>`.
    static func emitPolygon(
        _ node: PenNode,
        data: PenNode.PolygonData,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        // Pen strokes a sideless shape's per-side width at the top width alone.
        let data = data.drawn(on: node)
        let pad = String(repeating: " ", count: indent)
        let w = data.width?.fixedValue ?? 0
        let h = data.height?.fixedValue ?? 0
        let sides = Int(data.polygonCount?.literalValue ?? 3)

        let overflow = svgStrokeOverflows(data) ? " overflow=\"visible\"" : ""

        // Compute regular polygon points
        let cx = w / 2
        let cy = h / 2
        let rx = w / 2
        let ry = h / 2
        var points: [String] = []
        for i in 0 ..< sides {
            let angle = (Double(i) / Double(sides)) * 2 * .pi - .pi / 2
            let px = cx + rx * cos(angle)
            let py = cy + ry * sin(angle)
            points.append(String(format: "%.1f,%.1f", px, py))
        }
        let pointsStr = points.joined(separator: " ")

        var svgStyles: [(String, String)] = []
        svgStyles.append(contentsOf: emitFlexShrink(
            node, isRoot: isRoot,
            hasFixedWidth: data.width?.fixedValue != nil,
            hasFixedHeight: data.height?.fixedValue != nil,
            parentLayout: parentLayout
        ))
        svgStyles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
        svgStyles.append(contentsOf: turnedSlotStyles(node, width: data.width, height: data.height, isRoot: isRoot, ctx: ctx))
        svgStyles.append(contentsOf: filterEffectStyles(data.effects))

        if svgStyles.isEmpty {
            ctx.lines.append("\(pad)<svg width={\(Int(w))} height={\(Int(h))} viewBox=\"0 0 \(Int(w)) \(Int(h))\"\(overflow)>")
        } else {
            ctx.lines.append("\(pad)<svg width={\(Int(w))} height={\(Int(h))} viewBox=\"0 0 \(Int(w)) \(Int(h))\"\(overflow)")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in svgStyles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)>")
        }
        emitSVGShape(
            SVGStrokedShape(
                element: "polygon", geometry: "points=\"\(pointsStr)\"", fill: svgFillAttributes(data.fills),
                fillRule: nil, domain: .init(x: 0, y: 0, width: w, height: h), nodeID: node.id
            ),
            fills: data.fills, stroke: data, innerShadows: NodeEffects(data.effects).innerShadows, indent: indent + 2, ctx: ctx
        )
        ctx.lines.append("\(pad)</svg>")
    }

    // MARK: - Path

    /// Emits a path as an SVG `<path>`, mapping its `viewBox` onto the node box.
    static func emitPath(
        _ node: PenNode,
        data: PenNode.PathData,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        // Pen strokes a sideless shape's per-side width at the top width alone.
        let data = data.drawn(on: node)
        let pad = String(repeating: " ", count: indent)
        let w = Int(data.width?.fixedValue ?? 0)
        let h = Int(data.height?.fixedValue ?? 0)

        let geometry = data.geometry ?? ""
        let fillRule = data.fillRule?.rawValue

        // A viewBox maps its own region onto the node box with a non-uniform stretch,
        // and Pen draws whatever falls outside it rather than clipping. Without one, Pen
        // maps the geometry's tight bounds.
        let viewBox = data.viewBox ?? pathBounds(geometry, width: Double(w), height: Double(h))
        var svgAttrs = "width={\(w)} height={\(h)} viewBox=\"\(viewBox?.svgValue ?? "0 0 \(w) \(h)")\""
        if viewBox != nil {
            svgAttrs += " preserveAspectRatio=\"none\" overflow=\"visible\""
        } else if svgStrokeOverflows(data) {
            svgAttrs += " overflow=\"visible\""
        }

        var svgStyles: [(String, String)] = []
        svgStyles.append(contentsOf: emitFlexShrink(
            node, isRoot: isRoot,
            hasFixedWidth: data.width?.fixedValue != nil,
            hasFixedHeight: data.height?.fixedValue != nil,
            parentLayout: parentLayout
        ))
        svgStyles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
        svgStyles.append(contentsOf: turnedSlotStyles(node, width: data.width, height: data.height, isRoot: isRoot, ctx: ctx))
        svgStyles.append(contentsOf: filterEffectStyles(data.effects))

        if svgStyles.isEmpty {
            ctx.lines.append("\(pad)<svg \(svgAttrs)>")
        } else {
            ctx.lines.append("\(pad)<svg \(svgAttrs)")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in svgStyles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)>")
        }
        let domain = viewBox.map { SVGStrokedShape.Box(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
            ?? SVGStrokedShape.Box(x: 0, y: 0, width: Double(w), height: Double(h))
        let scale = viewBox.map { box in
            SVGStrokedShape.Scale(
                x: box.width > 0 ? Double(w) / box.width : 1,
                y: box.height > 0 ? Double(h) / box.height : 1
            )
        } ?? .identity
        emitSVGShape(
            SVGStrokedShape(
                element: "path", geometry: "d=\"\(geometry)\"", fill: svgFillAttributes(data.fills, fillRule: fillRule),
                fillRule: fillRule, domain: domain, nodeID: node.id, scale: scale
            ),
            fills: data.fills, stroke: data, innerShadows: NodeEffects(data.effects).innerShadows, indent: indent + 2, ctx: ctx
        )
        ctx.lines.append("\(pad)</svg>")
    }

    /// The region of a path's geometry Pen maps onto a `width` × `height` box when the path
    /// declares no viewBox: its tight bounds (``PenPath/sourceRegion(viewBox:)``), an axis
    /// with no extent keeping the box's so it is moved but not scaled. `nil` when the
    /// geometry has no points or its bounds already are the box, so nothing is stretched.
    private static func pathBounds(_ geometry: String, width: Double, height: Double) -> PenViewBox? {
        guard let bounds = PenPath(svg: geometry)?.sourceRegion(viewBox: nil) else { return nil }
        let region = PenViewBox(
            x: bounds.x, y: bounds.y,
            width: bounds.width > 0 ? bounds.width : width,
            height: bounds.height > 0 ? bounds.height : height
        )
        return region == PenViewBox(x: 0, y: 0, width: width, height: height) ? nil : region
    }

    // MARK: - Line

    /// Emits a line: a `<div>` with a top border at full width — or, for a stroke a colour
    /// cannot carry, a band as tall as the stroke, painted by its fills — otherwise an SVG
    /// `<line>` from the box's top-left corner to its bottom-right, as the renderer draws it.
    ///
    /// Pen centres a line's stroke on the line, so half of it lies above a flat line's
    /// `y`. Neither form lets the stroke move the layout: the SVG is grown by half the
    /// stroke on every side and pulled back by negative margins of the same, and the
    /// border's margins hand back the height it takes. A line with no stroke paint draws
    /// nothing, as Pen draws nothing (`render-unstroked-lines`), and its box keeps its size.
    static func emitLine(
        _ node: PenNode,
        data: PenNode.LineData,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        // Pen strokes a sideless shape's per-side width at the top width alone.
        let data = data.drawn(on: node)
        let pad = String(repeating: " ", count: indent)

        let strokeRoute = PaintRoute(data.stroke)
        let strokeColor = strokeRoute.plainColor.map(cssColorReference) ?? "currentColor"
        let strokeWidth = strokeRoute == .none ? 0 : data.uniformStrokeWidth ?? 1
        let halfWidth = strokeWidth / 2
        let nodeHeight = data.height?.fixedValue ?? 0

        let isFillContainer = if case .fillContainer = data.width { true } else { false }

        if isFillContainer {
            // Emit as a CSS div with border-top for full-width lines
            var styles = [("width", "\"100%\"")]
            if strokeRoute == .none {
                styles.append(("height", cssNumber(nodeHeight)))
            } else if let paintedStroke = strokeRoute.layeredFills {
                // A border takes one colour: a painted band is the stroke's own box.
                styles.append(("height", cssNumber(strokeWidth)))
                styles.append(contentsOf: emitFillStyles(
                    .multiple(paintedStroke), box: FillBox(width: nil, height: strokeWidth), ctx: ctx
                ))
                styles.append(("marginTop", cssNumber(-halfWidth)))
                styles.append(("marginBottom", cssNumber(nodeHeight - halfWidth)))
            } else {
                styles.append(("borderTop", "\"\(cssNumber(strokeWidth))px solid \(strokeColor)\""))
                styles.append(("marginTop", cssNumber(-halfWidth)))
                styles.append(("marginBottom", cssNumber(nodeHeight - halfWidth)))
            }
            styles.append(contentsOf: emitFlexShrink(
                node, isRoot: isRoot,
                hasFixedWidth: false,
                hasFixedHeight: data.height?.fixedValue != nil,
                parentLayout: parentLayout
            ))
            styles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
            styles.append(contentsOf: filterEffectStyles(data.effects))

            ctx.lines.append("\(pad)<div")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in styles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)/>")
        } else {
            let w = data.width?.fixedValue ?? 0
            let grown = (width: cssNumber(w + strokeWidth), height: cssNumber(nodeHeight + strokeWidth))
            let origin = cssNumber(-halfWidth)
            let svgAttrs = "width={\(grown.width)} height={\(grown.height)} "
                + "viewBox=\"\(origin) \(origin) \(grown.width) \(grown.height)\" overflow=\"visible\""

            var svgStyles: [(String, String)] = halfWidth == 0 ? [] : [("margin", cssNumber(-halfWidth))]
            svgStyles.append(contentsOf: emitFlexShrink(
                node, isRoot: isRoot,
                hasFixedWidth: data.width?.fixedValue != nil,
                hasFixedHeight: data.height?.fixedValue != nil,
                parentLayout: parentLayout
            ))
            svgStyles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
            svgStyles.append(contentsOf: filterEffectStyles(data.effects))

            ctx.lines.append("\(pad)<svg \(svgAttrs)")
            ctx.lines.append("\(pad)  style={{")
            for (key, value) in svgStyles {
                ctx.lines.append("\(pad)    \(key): \(value),")
            }
            ctx.lines.append("\(pad)  }}")
            ctx.lines.append("\(pad)>")
            let geometry = "x1=\"0\" y1=\"0\" x2=\"\(cssNumber(w))\" y2=\"\(cssNumber(nodeHeight))\""
            if let paintedStroke = strokeRoute.layeredFills {
                emitPaintedSVGShape(
                    SVGStrokedShape(
                        element: "line", geometry: geometry, fill: nil, fillRule: nil,
                        domain: lineBand(width: w, height: nodeHeight, strokeWidth: strokeWidth), nodeID: node.id
                    ),
                    fills: paintedStroke, stroke: data, indent: indent + 2, ctx: ctx
                )
            } else if strokeRoute != .none {
                let strokeAttributes = "stroke=\"\(strokeColor)\" strokeWidth=\"\(cssNumber(strokeWidth))\"\(svgStrokeStyle(data))"
                ctx.lines.append("\(pad)  <line \(geometry) \(strokeAttributes) />")
            }
            ctx.lines.append("\(pad)</svg>")
        }
    }

    /// The box a line's stroke paint is laid over: the line's own box, or — on an axis where
    /// the line has no extent, which would collapse the paint's geometry and draw nothing —
    /// the stroke's band across it, as a full-width line's band is painted.
    static func lineBand(width: Double, height: Double, strokeWidth: Double) -> SVGStrokedShape.Box {
        SVGStrokedShape.Box(
            x: width == 0 ? -strokeWidth / 2 : 0,
            y: height == 0 ? -strokeWidth / 2 : 0,
            width: width == 0 ? strokeWidth : width,
            height: height == 0 ? strokeWidth : height
        )
    }
}
