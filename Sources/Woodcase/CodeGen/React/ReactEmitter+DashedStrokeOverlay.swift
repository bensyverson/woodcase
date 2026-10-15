//
//  ReactEmitter+DashedStrokeOverlay.swift
//  Woodcase
//

extension ReactEmitter {
    /// The SVG overlay that draws a box's dashed stroke — a frame's or a rectangle's — or
    /// `nil` when the node has no dash, nothing to paint, or a size not known at generate
    /// time (warned once; the stroke is then drawn solid by CSS).
    ///
    /// CSS's `dashed` border cannot say a dash's lengths or where it starts, so the stroke
    /// is an absolutely placed SVG over the node's box, stroking the renderer's own outline
    /// (``PenShapeGeometry``) — which starts where the renderer's dashes start, at
    /// `(x + r, y)`, and runs clockwise — with `stroke-dasharray` and `stroke-dashoffset`.
    /// An inner or outer stroke is drawn at twice its width and cut to the shape or its
    /// complement, as every SVG stroke is (``emitPaintedSVGShape(_:fills:stroke:indent:ctx:)``).
    ///
    /// - Parameters:
    ///   - node: The node, for its dash and its outline.
    ///   - stroke: Its stroke keys.
    ///   - box: Its box.
    ///   - beneathChildren: Whether the overlay must paint under the node's children, as
    ///     Pen draws a container's stroke before them; the host must then isolate.
    ///   - ctx: The emission context.
    /// - Returns: The overlay layer.
    static func dashedStrokeOverlay(
        _ node: PenNode,
        stroke: any PenStrokable,
        box: FillBox,
        beneathChildren: Bool,
        ctx: EmitContext
    ) -> FillLayer? {
        guard let dash = node.strokeDash else { return nil }
        let route = PaintRoute(stroke.stroke)
        guard let fills = route.layeredFills ?? route.plainColor.map({ [PenFill.color(PenFill.PenColorFill(color: $0))] })
        else { return nil }
        guard let width = box.width, let height = box.height,
              let outline = PenShapeGeometry.outline(for: node, rect: PenRect(x: 0, y: 0, width: width, height: height))
        else {
            ctx.warnOnce(unsizedDashWarning, nodeID: node.id)
            return nil
        }

        let shape = SVGStrokedShape(
            element: "path", geometry: "d=\"\(outline.svgPathData { cssNumber($0, decimals: 3) })\"", fill: "fill=\"none\"",
            fillRule: nil, domain: .init(x: 0, y: 0, width: width, height: height), nodeID: node.id, dash: dash
        )
        let saved = ctx.lines
        ctx.lines = []
        emitPaintedSVGShape(shape, fills: fills, stroke: stroke, indent: 2, ctx: ctx)
        let drawn = ctx.lines
        ctx.lines = saved

        let svg = ["<svg width={\(cssNumber(width))} height={\(cssNumber(height))} overflow=\"visible\">"]
            + drawn + ["</svg>"]
        var styles = [("position", "\"absolute\""), ("inset", "0")]
        if beneathChildren {
            styles.append(("zIndex", "-1"))
        }
        styles.append(("pointerEvents", "\"none\""))
        return FillLayer(styles, content: svg.joined(separator: "\n"))
    }

    /// What generation says when a dashed box's size is only known at layout time.
    static let unsizedDashWarning =
        "A dashed stroke on a box whose size is only known at layout time is drawn solid: "
            + "the dashes follow an outline of a known size."
}
