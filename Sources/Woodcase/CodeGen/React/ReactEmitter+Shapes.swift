//
//  ReactEmitter+Shapes.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    // MARK: - Rectangle

    /// Emits a rectangle as a `<div>`, holding a stroke overlay when its stroke is painted.
    static func emitRectangle(
        _ node: PenNode,
        data: PenNode.RectangleData,
        indent: Int,
        ctx: EmitContext,
        isRoot: Bool,
        parentLayout: PenLayoutDirection? = nil
    ) {
        let pad = String(repeating: " ", count: indent)
        var styles: [(String, String)] = []

        let placement = ctx.placement(for: node.common)
        if let width = data.width, let cssWidth = emitSizing(width, placement: placement, fitsContent: false) {
            styles.append(("width", cssWidth))
        }
        if let height = data.height, let cssHeight = emitSizing(height, placement: placement, fitsContent: false) {
            styles.append(("height", cssHeight))
        }

        let shadowLayers = shadowLayerStyles(data.effects, borderRadius: data.cornerRadius.flatMap(emitCornerRadius), stroke: data)
        let box = FillBox(width: data.width, height: data.height)
        let fills = PaintSplit(data.fills)
        styles.append(contentsOf: emitVisualStyles(
            fills: fills.backgroundFills,
            box: box,
            cornerRadius: data.cornerRadius,
            stroke: data,
            effects: data.effects,
            showsBackdrop: data.fills?.hasVisiblePaint == true,
            layered: shadowLayers != nil,
            ctx: ctx
        ))
        let layersOverFill = liftingInsetShadows(
            &styles, over: fillLayers(fills.layered, box: box, beneathChildren: false, ctx: ctx), beneathChildren: false
        )
        let overlay = strokeOverlay(data, shape: .box(data.cornerRadius), beneathChildren: false, box: box, ctx: ctx)
        if overlay != nil || shadowLayers != nil || !layersOverFill.isEmpty {
            styles.append(("position", "\"relative\""))
        }

        styles.append(contentsOf: emitFlexShrink(
            node, isRoot: isRoot,
            hasFixedWidth: data.width?.fixedValue != nil,
            hasFixedHeight: data.height?.fixedValue != nil,
            parentLayout: parentLayout
        ))
        styles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
        styles.append(contentsOf: turnedSlotStyles(node, width: data.width, height: data.height, isRoot: isRoot, ctx: ctx))

        // var() substitution for state-affected properties
        substituteStateVars(&styles, pivot: ctx.transformPivot(for: node.common), ctx: ctx)

        if styles.isEmpty {
            ctx.lines.append("\(pad)<div />")
        } else {
            emitBoxElement(styles, shadowLayers: shadowLayers, fillLayers: layersOverFill, overlay: overlay, indent: indent, ctx: ctx)
        }
    }

    // MARK: - Ellipse

    /// Emits an ellipse: an SVG path for an arc or a donut, otherwise a `<div>` with
    /// `border-radius: 50%`, holding a stroke overlay when its stroke is painted.
    static func emitEllipse(
        _ node: PenNode,
        data: PenNode.EllipseData,
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
        if !drawsAsBox(data) {
            // SVG ellipse for donut/arc
            let overflow = svgStrokeOverflows(data) ? " overflow=\"visible\"" : ""

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

            // The renderer's own outline and fill rule: a pie slice, a ring or an arc donut.
            let outline = PenShapeGeometry.outline(for: node, rect: PenRect(x: 0, y: 0, width: w, height: h))
            let d = outline?.svgPathData { cssNumber($0, decimals: 3) } ?? ""
            let fillRule = PenShapeGeometry.fillRule(for: node) == .evenodd ? PenFillRule.evenodd.rawValue : nil
            emitSVGShape(
                SVGStrokedShape(
                    element: "path", geometry: "d=\"\(d)\"", fill: svgFillAttributes(data.fills, fillRule: fillRule),
                    fillRule: fillRule, domain: .init(x: 0, y: 0, width: w, height: h), nodeID: node.id
                ),
                fills: data.fills, stroke: data, innerShadows: NodeEffects(data.effects).innerShadows,
                indent: indent + 2, ctx: ctx
            )

            ctx.lines.append("\(pad)</svg>")
        } else {
            // Simple CSS ellipse
            var styles: [(String, String)] = []

            let placement = ctx.placement(for: node.common)
            if let width = data.width, let cssWidth = emitSizing(width, placement: placement, fitsContent: false) {
                styles.append(("width", cssWidth))
            }
            if let height = data.height, let cssHeight = emitSizing(height, placement: placement, fitsContent: false) {
                styles.append(("height", cssHeight))
            }

            styles.append(("borderRadius", "\"50%\""))

            let shadowLayers = shadowLayerStyles(data.effects, borderRadius: "\"50%\"", stroke: data)
            let box = FillBox(width: data.width, height: data.height)
            let fills = PaintSplit(data.fills)
            styles.append(contentsOf: emitVisualStyles(
                fills: fills.backgroundFills,
                box: box,
                cornerRadius: nil,
                stroke: data,
                effects: data.effects,
                showsBackdrop: data.fills?.hasVisiblePaint == true,
                layered: shadowLayers != nil,
                ctx: ctx
            ))
            let layersOverFill = liftingInsetShadows(
                &styles, over: fillLayers(fills.layered, box: box, beneathChildren: false, ctx: ctx), beneathChildren: false
            )
            let overlay = strokeOverlay(data, shape: .ellipse, beneathChildren: false, box: box, ctx: ctx)
            if overlay != nil || shadowLayers != nil || !layersOverFill.isEmpty {
                styles.append(("position", "\"relative\""))
            }

            styles.append(contentsOf: emitFlexShrink(
                node, isRoot: isRoot,
                hasFixedWidth: data.width?.fixedValue != nil,
                hasFixedHeight: data.height?.fixedValue != nil,
                parentLayout: parentLayout
            ))
            styles.append(contentsOf: emitCommonStyles(node.common, blendMode: data.blendMode, pivot: ctx.transformPivot(for: node.common)))
            styles.append(contentsOf: turnedSlotStyles(node, width: data.width, height: data.height, isRoot: isRoot, ctx: ctx))

            emitBoxElement(styles, shadowLayers: shadowLayers, fillLayers: layersOverFill, overlay: overlay, indent: indent, ctx: ctx)
        }
    }
}
