//
//  SwiftUINodeEmitter+Silhouette.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// What a shape's outer shadows are cast by, in both the shape and the box it is drawn in.
    ///
    /// Pen casts an outer shadow from what the node paints, each paint opaque: its outline
    /// where a fill paints, united with its stroke's band where the stroke paints, and knocks
    /// the shadow out under all of it (`render-stroke-shadows.pen`, `render-content-shadows.pen`),
    /// as the renderer's `PenShadowSilhouette` does.
    struct Silhouette: Friendly {
        /// The node's outline, which its background blur is drawn in.
        var outline: Outline

        /// The shape the shadow is cast by — the outline, its band, or
        /// `PenSilhouette(outline, stroke: band)` — or `nil` when the node paints nothing,
        /// and so casts no shadow.
        var cast: String?

        /// How far the box the silhouette is drawn in grows, for a box under a point on an axis,
        /// which SwiftUI would not draw; `nil` when it is drawn in the node's own box.
        var outset: FlatOutset?

        /// Whether `cast` must be filled even-odd to draw correctly: an even-odd outline with
        /// no stroke band, where `PenSilhouette`'s own union has not already normalized it.
        var eoFill = false

        /// The arguments after a shadow's own: `, outset: CGSize(width: 8, height: 8)`, or nothing.
        var outsetArgument: String {
            guard let outset else { return "" }
            let n = SwiftUILiteral.number
            return ", outset: CGSize(width: \(n(outset.dx)), height: \(n(outset.dy)))"
        }

        /// The argument after `outsetArgument` when `cast` needs an even-odd fill:
        /// `, eoFill: true`, or nothing.
        var eoFillArgument: String {
            eoFill ? ", eoFill: true" : ""
        }
    }

    /// The silhouette of a node drawn as `shape` in `box`, painted by `fills` and stroked by
    /// `stroke`.
    ///
    /// The outline casts when a fill paints (``castsPaint(_:)``), however translucent; a line
    /// has no inside. The band is the region a painted stroke covers, laid out as
    /// ``strokeView(_:shape:box:dash:miterLimit:overFills:unemitted:)`` lays it out — per
    /// side, from the box on a 0×0 box, or the outline's own stroke — and a line's always
    /// centered on it (`render-stroke-shadows.pen`, boards `line-diagonal` and `line-flat`).
    /// An inside stroke over a fill that paints adds nothing, since the outline covers it.
    ///
    /// - Parameters:
    ///   - node: The node, for its kind.
    ///   - shape: Its outline, as drawn in its own box.
    ///   - fills: Its fills.
    ///   - stroke: Its stroke, as ``PenStrokable/drawn(on:)`` gives it, or `nil`.
    ///   - box: The node's box.
    ///   - outset: How far a stroke on a box under a point grows the box it is drawn in.
    func silhouette(
        of node: PenNode, shape: Outline, fills: PenFills?, stroke: (any PenStrokable)?, box: FillBox, outset: FlatOutset?
    ) -> Silhouette {
        let isLine = if case .line = node.kind { true } else { false }
        let filled = !isLine && Self.castsPaint(fills)
        let band = stroke.flatMap { band($0, shape: shape, box: box, isLine: isLine, filled: filled) }
        switch (filled, band) {
        case let (true, band?):
            let eoFill = shape.evenOdd ? ", eoFill: true" : ""
            return Silhouette(outline: shape, cast: "PenSilhouette(\(shape.view), stroke: \(band)\(eoFill))", outset: outset)
        case (true, nil):
            return Silhouette(outline: shape, cast: shape.view, eoFill: shape.evenOdd)
        case let (false, band?):
            return Silhouette(outline: shape, cast: band, outset: outset)
        case (false, nil):
            return Silhouette(outline: shape, cast: nil)
        }
    }

    /// The region a stroke covers that a shadow is cast by, or `nil` when there is none: no
    /// paint that casts, no width or a zero one, an inside stroke over a fill that paints, or
    /// a width the theme cannot read (which the stroke itself reports).
    private func band(_ stroke: any PenStrokable, shape: Outline, box: FillBox, isLine: Bool, filled: Bool) -> String? {
        guard Self.castsPaint(stroke.stroke) else { return nil }
        let alignment: PenStrokeAlign = isLine ? .center : stroke.strokeAlignment ?? .center
        guard !(filled && alignment == .inner) else { return nil }
        var reported: [String] = []
        let width: SwiftUINumber
        switch stroke.strokeWidth {
        case let .perSide(sides):
            guard let corners = shape.corners, let widths = sideWidths(sides, unemitted: &reported) else { return nil }
            return sideRegion(widths, alignment: alignment, shape: shape, corners: corners).view
        case let .uniform(value):
            guard let number = number(value, unemitted: &reported) else { return nil }
            width = number
        case nil:
            return nil
        }
        guard width.largest > 0 else { return nil }
        if !isLine, box.width == 0, box.height == 0, let corners = shape.corners {
            let widths = EdgeValues(top: width, right: width, bottom: width, left: width)
            return sideRegion(widths, alignment: alignment, shape: shape, corners: corners).view
        }
        let style = strokeStyle(width.code, cap: stroke.strokeLinecap, join: stroke.strokeLinejoin)
        return "\(shape.view).penStroke(.\(SwiftUIStrokeAlignment(alignment).rawValue), \(style))"
    }
}
