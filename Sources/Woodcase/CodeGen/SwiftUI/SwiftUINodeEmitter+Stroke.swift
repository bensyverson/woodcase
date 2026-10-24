//
//  SwiftUINodeEmitter+Stroke.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// The view that draws a node's stroke in its box, or `nil` when it draws none: no
    /// enabled paint, no width or a zero one, or a width that names a variable the theme has no
    /// number for (reported in `unemitted`). A uniform or per-side width the theme has a
    /// number for is read through it.
    ///
    /// The stroke is painted like a fill, over the node's box (``paintLayers(_:box:of:overPaints:unemitted:)``),
    /// through the region it covers. A centered stroke of one paint is SwiftUI's own
    /// `.stroke`, and an inside one on a rectangle whose corners are at least half the width
    /// is `.strokeBorder`, which then draws exactly Pen's band. Everything else is a support
    /// shape — `penStroke(_:lineWidth:)` for an alignment SwiftUI does not draw, a stack of
    /// paints, or a paint that is a view; `PenSideStroke` for a width per side on a box, or
    /// for any width on a 0×0 box, where there is no outline to stroke —
    /// filled or clipped to like a node's outline. A sideless shape is handed its stroke as
    /// ``PenStrokable/drawn(on:)`` gives it: Pen strokes a per-side width there at the top
    /// width alone, so it arrives uniform; a per-side width on a shape without corners
    /// draws nothing. A dash (``PenNode/strokeDash``) goes in the uniform stroke's
    /// `StrokeStyle` — SwiftUI's own shapes start their outlines where they choose, so its
    /// dashes need not start where the renderer's do; a per-side band takes none. A
    /// `miterLimit` (``writtenMiterLimit(of:)``) goes in the same `StrokeStyle`. With
    /// `overFills` false, the stroke's lowest paint is the node's lowest and is written
    /// without its blend mode (``paintLayers(_:box:of:overPaints:unemitted:)``).
    func strokeView(
        _ stroke: any PenStrokable, shape: Outline, box: FillBox, dash: PenStrokeDash? = nil, miterLimit: Double? = nil,
        overFills: Bool, unemitted: inout [String]
    ) -> SwiftUIViewCode? {
        guard PaintRoute(stroke.stroke) != .none else { return nil }
        let region: Outline
        switch stroke.strokeWidth {
        case let .perSide(sides):
            guard let corners = shape.corners, let widths = sideWidths(sides, unemitted: &unemitted) else { return nil }
            let layers = paintLayers(stroke.stroke, box: box, overPaints: overFills, unemitted: &unemitted)
            guard !layers.isEmpty else { return nil }
            let alignment = stroke.strokeAlignment ?? .center
            region = sideRegion(widths, alignment: alignment, shape: shape, corners: corners)
            let widest = max(widths.top.largest, widths.right.largest, widths.bottom.largest, widths.left.largest)
            return painted(region, layers: layers, reach: widest * Self.outsideShare(alignment))
        case let .uniform(value):
            guard let width = number(value, unemitted: &unemitted) else { return nil }
            return uniformStroke(
                stroke, width: width, shape: shape, box: box, dash: dash, miterLimit: miterLimit, overFills: overFills,
                unemitted: &unemitted
            )
        case nil:
            // No width is no stroke, as Pen draws it.
            return nil
        }
    }

    /// A stroke of one width all round; a width read through the theme reaches as far as
    /// its widest value.
    private func uniformStroke(
        _ stroke: any PenStrokable, width number: SwiftUINumber, shape: Outline, box: FillBox, dash: PenStrokeDash?,
        miterLimit: Double?, overFills: Bool, unemitted: inout [String]
    ) -> SwiftUIViewCode? {
        guard number.largest > 0 else { return nil }
        let width = number.largest
        let layers = paintLayers(stroke.stroke, box: box, overPaints: overFills, unemitted: &unemitted)
        guard !layers.isEmpty else { return nil }
        let alignment = stroke.strokeAlignment ?? .center
        // A box that is a point — a sizeless `layout: none` frame — has no outline to stroke,
        // and Pen still paints the band about it; lay it out from the box, as per side.
        if box.width == 0, box.height == 0, let corners = shape.corners {
            let widths = EdgeValues(top: number, right: number, bottom: number, left: number)
            let region = sideRegion(widths, alignment: alignment, shape: shape, corners: corners)
            return painted(region, layers: layers, reach: width * Self.outsideShare(alignment))
        }
        let style = strokeStyle(
            number.code, cap: stroke.strokeLinecap, join: stroke.strokeLinejoin, dash: dash, miterLimit: miterLimit
        )
        if layers.count == 1, let paint = layers[0].style {
            if alignment == .center {
                return SwiftUIViewCode(head: shape.view).modified(".stroke(\(paint), \(style))")
            }
            if alignment == .inner, number.values.allSatisfy(shape.bordersExactly(width:)) {
                return SwiftUIViewCode(head: shape.view).modified(".strokeBorder(\(paint), \(style))")
            }
        }
        let name = SwiftUIStrokeAlignment(alignment).rawValue
        let region = "\(shape.view).penStroke(.\(name), \(style))"
        // A miter can reach half the miter limit's widths past the outline's corner.
        let joinReach = (stroke.strokeLinejoin ?? .miter) == .miter ? miterLimit ?? Self.miterLimit : 2
        let reach = width * Self.outsideShare(alignment) * joinReach
        return painted(Outline(view: region, argument: region), layers: layers, reach: reach)
    }

    /// SwiftUI's and Core Graphics' default miter limit. Pen strokes with 4
    /// (``PenNode/defaultMiterLimit``), which ``writtenMiterLimit(of:)`` writes where it
    /// can differ.
    private static let miterLimit = 10.0

    /// The miter limit a node's `StrokeStyle` names, or `nil` where SwiftUI's own 10 draws
    /// the same as the node's limit (``PenNode/strokeMiterLimit``, Pen's 4 by default).
    ///
    /// The two draw a corner alike unless its miter (`CGPath.miterRatios`)
    /// falls between them, so the limit is written only for a shape with such a corner,
    /// read off its outline at its declared size: a sharp path, star or arc, never a
    /// rectangle, a plain ellipse or a line, which has no corners. A path, polygon or
    /// ellipse whose size is only known at layout time is given the limit whenever it
    /// differs from 10; a box's corners are right angles at any size.
    ///
    /// - Parameter node: The stroked node.
    /// - Returns: The limit to write, or `nil`.
    static func writtenMiterLimit(of node: PenNode) -> Double? {
        let limit = node.strokeMiterLimit
        if case .line = node.kind { return nil }
        guard limit != miterLimit else { return nil }
        let sized: (any PenLayoutSized)? = switch node.kind {
        case let .frame(data): data
        case let .rectangle(data): data
        case let .ellipse(data): data
        case let .polygon(data): data
        case let .path(data): data
        default: nil
        }
        // A box's corners are right angles at any size; any other outline's depend on it.
        let isBox = switch node.kind {
        case .frame, .rectangle: true
        default: false
        }
        let box: PenRect? = if let width = sized?.width?.fixedValue, let height = sized?.height?.fixedValue {
            PenRect(x: 0, y: 0, width: width, height: height)
        } else if isBox {
            PenRect(x: 0, y: 0, width: 100, height: 100)
        } else {
            nil
        }
        guard let box, let outline = PenShapeBuilder.buildPath(for: node, rect: box) else { return limit }
        let low = min(limit, miterLimit), high = max(limit, miterLimit)
        return outline.miterRatios.contains { $0 > low && $0 <= high } ? limit : nil
    }

    /// How much of a stroke's width lies outside the outline.
    private static func outsideShare(_ alignment: PenStrokeAlign) -> Double {
        switch alignment {
        case .inner: 0
        case .center: 0.5
        case .outer: 1
        }
    }

    /// `layers` painted through `region`, clipped to it when a layer is a view. A view
    /// that is drawn past its box when given room is given `reach` points of it, for a
    /// stroke that reaches that far outside the box.
    private func painted(_ region: Outline, layers: [SwiftUIPaintLayer], reach: Double) -> SwiftUIViewCode {
        var view = paintedShape(region, layers: layers)
        guard needsClip(layers) else { return view }
        if reach > 0, layers.contains(where: \.extendsPastBox) {
            view = view.modified(".penPaintBleed(\(SwiftUILiteral.number(reach)))")
        }
        return clip(view, to: region)
    }

    /// The width and style arguments: `lineWidth: 2`, or a `StrokeStyle` naming the cap and
    /// join where they are not SwiftUI's defaults, which are Pen's (butt, miter), and the
    /// dash and its phase when there is one, and the miter limit on a mitered join when one
    /// is given.
    func strokeStyle(
        _ width: String, cap: PenStrokeCap?, join: PenStrokeJoin?, dash: PenStrokeDash? = nil, miterLimit: Double? = nil
    ) -> String {
        var parts = ["lineWidth: \(width)"]
        if let cap, cap != .butt {
            parts.append("lineCap: .\(cap.rawValue)")
        }
        if let join, join != .miter {
            parts.append("lineJoin: .\(join.rawValue)")
        }
        if let miterLimit, (join ?? .miter) == .miter {
            parts.append("miterLimit: \(SwiftUILiteral.number(miterLimit))")
        }
        if let dash {
            parts.append("dash: [\(dash.lengths.map(SwiftUILiteral.number).joined(separator: ", "))]")
            if dash.phase != 0 {
                parts.append("dashPhase: \(SwiftUILiteral.number(dash.phase))")
            }
        }
        return parts.count == 1 ? parts[0] : "style: StrokeStyle(\(parts.joined(separator: ", ")))"
    }

    /// A per-side stroke's four widths, a missing side zero and a theme read wherever a side
    /// names a number variable the theme has; `nil` when a side names one it does not
    /// (reported) or every side is zero under every theme.
    func sideWidths(_ sides: PenStrokeWidth.Sides, unemitted: inout [String]) -> EdgeValues? {
        var values: [SwiftUINumber] = []
        for side in [sides.top, sides.right, sides.bottom, sides.left] {
            guard var value = number(side, unemitted: &unemitted) else { return nil }
            if let literal = value.literal, literal < 0 { value = SwiftUINumber(0) }
            values.append(value)
        }
        guard values.contains(where: { !$0.isZero }) else { return nil }
        return EdgeValues(top: values[0], right: values[1], bottom: values[2], left: values[3])
    }

    /// The region a per-side stroke covers: `PenSideStroke` on the box `corners` rounds,
    /// drawn inside the box it is offered when the box is flat (``Outline/flatOutset``).
    func sideRegion(
        _ widths: EdgeValues, alignment: PenStrokeAlign, shape: Outline, corners: PenCornerRadius.Corners
    ) -> Outline {
        let insets = "EdgeInsets(top: \(widths.top.code), leading: \(widths.left.code), "
            + "bottom: \(widths.bottom.code), trailing: \(widths.right.code))"
        var arguments = [insets, "alignment: .\(SwiftUIStrokeAlignment(alignment).rawValue)"]
        let numbers = shape.radii ?? [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft].map(SwiftUINumber.init)
        let radii = [
            ("topLeading", numbers[0]), ("bottomLeading", numbers[3]),
            ("bottomTrailing", numbers[2]), ("topTrailing", numbers[1]),
        ].filter { $0.1.largest > 0 }.map { "\($0.0): \($0.1.code)" }
        if !radii.isEmpty {
            arguments.append("cornerRadii: RectangleCornerRadii(\(radii.joined(separator: ", ")))")
        }
        let region = "PenSideStroke(\(arguments.joined(separator: ", ")))" + (shape.flatOutset?.modifier ?? "")
        return Outline(view: region, argument: region)
    }

    /// Four lengths, one per side of a box; each a literal or a theme read.
    struct EdgeValues: Friendly {
        /// The top side.
        var top: SwiftUINumber
        /// The right side.
        var right: SwiftUINumber
        /// The bottom side.
        var bottom: SwiftUINumber
        /// The left side.
        var left: SwiftUINumber
    }
}
