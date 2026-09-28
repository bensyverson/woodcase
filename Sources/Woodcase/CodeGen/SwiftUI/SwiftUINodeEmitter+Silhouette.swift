//
//  SwiftUINodeEmitter+Silhouette.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// What a shape's outer shadows are cast by, in both the shape and the box it is drawn in.
    ///
    /// Pen casts an outer shadow from what the node covers: its outline, grown by the part of
    /// its stroke band that lies outside it, and knocks the shadow out under all of it
    /// (`render-stroke-shadows.pen`), as the renderer's `PenShadowSilhouette` does.
    struct Silhouette: Friendly {
        /// The node's outline, which its background blur is drawn in.
        var outline: Outline

        /// The shape the shadow is cast by: the outline, or `PenSilhouette(outline, stroke: band)`.
        var cast: String

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

    /// The silhouette of a node drawn as `shape` in `box`, stroked by `stroke`.
    ///
    /// The band is the region the stroke covers, laid out as ``strokeView(_:shape:box:unemitted:)``
    /// lays it out — per side, from the box on a 0×0 box, or the outline's own stroke — and
    /// only where it can reach outside the shape: an inside stroke adds nothing. A line casts
    /// nothing from its stroke, which is what Pen draws (`render-stroke-shadows.pen`, boards
    /// `line-diagonal` and `line-flat`); its outline, filled, is empty.
    ///
    /// - Parameters:
    ///   - node: The node, for its kind.
    ///   - shape: Its outline, as drawn in its own box.
    ///   - stroke: Its stroke, as ``PenStrokable/drawn(on:)`` gives it, or `nil`.
    ///   - box: The node's box.
    ///   - outset: How far a stroke on a box under a point grows the box it is drawn in.
    func silhouette(
        of node: PenNode, shape: Outline, stroke: (any PenStrokable)?, box: FillBox, outset: FlatOutset?
    ) -> Silhouette {
        let plain = Silhouette(outline: shape, cast: shape.view, eoFill: shape.evenOdd)
        if case .line = node.kind { return plain }
        guard let stroke, let band = outsideBand(stroke, shape: shape, box: box) else { return plain }
        let eoFill = shape.evenOdd ? ", eoFill: true" : ""
        return Silhouette(outline: shape, cast: "PenSilhouette(\(shape.view), stroke: \(band)\(eoFill))", outset: outset)
    }

    /// The region a stroke covers that can lie outside `shape`, or `nil` when none can: no
    /// enabled paint, a zero width, an inside stroke, or a width the theme cannot read (which
    /// the stroke itself reports).
    private func outsideBand(_ stroke: any PenStrokable, shape: Outline, box: FillBox) -> String? {
        guard PaintRoute(stroke.stroke) != .none else { return nil }
        let alignment = stroke.strokeAlignment ?? .center
        guard alignment != .inner else { return nil }
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
            width = SwiftUINumber(1)
        }
        guard width.largest > 0 else { return nil }
        if box.width == 0, box.height == 0, let corners = shape.corners {
            let widths = EdgeValues(top: width, right: width, bottom: width, left: width)
            return sideRegion(widths, alignment: alignment, shape: shape, corners: corners).view
        }
        let style = strokeStyle(width.code, cap: stroke.strokeLinecap, join: stroke.strokeLinejoin)
        return "\(shape.view).penStroke(.\(SwiftUIStrokeAlignment(alignment).rawValue), \(style))"
    }
}
