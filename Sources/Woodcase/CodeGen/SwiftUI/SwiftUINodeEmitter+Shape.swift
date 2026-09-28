//
//  SwiftUINodeEmitter+Shape.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// A node's outline in both spellings SwiftUI wants: a view to draw
    /// (`RoundedRectangle(cornerRadius: 8, style: .circular)`) and a shape argument for
    /// `background(_:in:)` and `clipShape(_:)` (`.rect(cornerRadius: 8, style: .circular)`).
    ///
    /// Corners are `.circular`, which is what Pen draws; SwiftUI's default is `.continuous`.
    struct Outline: Friendly {
        /// The shape as a view.
        var view: String

        /// The shape as an argument.
        var argument: String

        /// The corner radii when the shape is a box — a rectangle, rounded or not — which a
        /// per-side stroke is laid out on; `nil` for any other shape. A radius read through
        /// the theme is its smallest value here, for the decisions that need a number.
        var corners: PenCornerRadius.Corners?

        /// The corner radii as the source writes them — top left, top right, bottom right,
        /// bottom left — when one is read through the theme; `nil` when ``corners`` says it.
        var radii: [SwiftUINumber]?

        /// How far the shape is drawn inside the box it is offered, when it is a box under a
        /// point on an axis (``outset(_:)``); `nil` when it fills its box.
        var flatOutset: FlatOutset?

        /// Whether the shape is filled and clipped even-odd: a path that declares it, and a
        /// ring, whose hole is a second subpath.
        var evenOdd = false

        /// The fill style argument after a paint, `, style: FillStyle(eoFill: true)` for an
        /// even-odd shape and nothing otherwise; `label` names the parameter.
        func fillStyle(label: String = "style") -> String {
            evenOdd ? ", \(label): FillStyle(eoFill: true)" : ""
        }

        /// This shape drawn `outset`'s reach inside the box it is offered
        /// (`penOutset(dx:dy:)`), for a stroke whose box ``FlatOutset`` grows. A box keeps its
        /// corners, so a per-side stroke is still laid out on its sides, but no longer fills
        /// the box it is offered, so a stroke on it is never a `strokeBorder`.
        func outset(_ outset: FlatOutset) -> Outline {
            let drawn = "\(view)\(outset.modifier)"
            return Outline(view: drawn, argument: drawn, corners: corners, radii: radii, flatOutset: outset, evenOdd: evenOdd)
        }

        /// A plain rectangle.
        static let rectangle = Outline(view: "Rectangle()", argument: ".rect", corners: .zero)

        /// An ellipse.
        static let ellipse = Outline(view: "Ellipse()", argument: ".ellipse")

        /// Whether SwiftUI's `strokeBorder` at `width` draws exactly Pen's inside stroke:
        /// on a box whose every rounded corner is at least half the width, the inset
        /// shape's stroke keeps the outer edge on the outline. A tighter corner would lose
        /// its rounding, and an ellipse's inset is not its offset.
        func bordersExactly(width: Double) -> Bool {
            guard let corners, flatOutset == nil else { return false }
            return [corners.topLeft, corners.topRight, corners.bottomRight, corners.bottomLeft]
                .allSatisfy { $0 <= 0 || $0 >= width / 2 }
        }
    }

    /// The rectangle `radius` rounds, or a plain one; a radius that names a variable reads
    /// the theme's number, and one the theme lacks is reported in `unemitted` and drawn
    /// square.
    func outline(_ radius: PenCornerRadius?, unemitted: inout [String]) -> Outline {
        guard let radius else { return .rectangle }
        let values: [PenValue<Double>] = switch radius {
        case let .uniform(value): [value, value, value, value]
        case let .perCorner(topLeft, topRight, bottomRight, bottomLeft): [topLeft, topRight, bottomRight, bottomLeft]
        }
        let radii = values.compactMap { number($0, unemitted: &unemitted) }
        guard radii.count == 4 else { return .rectangle }
        let corners = PenCornerRadius.Corners(
            topLeft: radii[0].smallest, topRight: radii[1].smallest,
            bottomRight: radii[2].smallest, bottomLeft: radii[3].smallest
        )
        let themed = radii.contains { $0.literal == nil } ? radii : nil
        if Set(radii.map(\.code)).count == 1 {
            guard radii[0].largest > 0 else { return .rectangle }
            let r = radii[0].code
            return Outline(
                view: "RoundedRectangle(cornerRadius: \(r), style: .circular)",
                argument: ".rect(cornerRadius: \(r), style: .circular)",
                corners: corners, radii: themed
            )
        }
        let arguments = ([
            ("topLeadingRadius", radii[0]), ("bottomLeadingRadius", radii[3]),
            ("bottomTrailingRadius", radii[2]), ("topTrailingRadius", radii[1]),
        ].filter { $0.1.largest > 0 }.map { "\($0.0): \($0.1.code)" } + ["style: .circular"]).joined(separator: ", ")
        return Outline(
            view: "UnevenRoundedRectangle(\(arguments))", argument: ".rect(\(arguments))", corners: corners, radii: themed
        )
    }

    /// A rectangle: its outline filled with its colours, at its size, stroked.
    func rectangle(_ node: PenNode, data: PenNode.RectangleData, in container: Container) -> SwiftUIViewCode {
        var unemitted: [String] = []
        let shape = outline(data.cornerRadius, unemitted: &unemitted)
        return filledShape(node, shape: shape, fills: data.fills, stroke: data, effects: data.effects, in: container, unemitted: unemitted)
    }

    /// An ellipse: filled with its colours, at its size, stroked. An arc or a donut is a
    /// shape of its own (``geometry(_:in:)``).
    func ellipse(_ node: PenNode, data: PenNode.EllipseData, in container: Container) -> SwiftUIViewCode {
        if isArc(data) {
            return geometry(node, in: container)
        }
        return filledShape(node, shape: .ellipse, fills: data.fills, stroke: data, effects: data.effects, in: container, unemitted: [])
    }

    /// Whether an ellipse is an arc or a donut, which ``geometry(_:in:)`` draws.
    func isArc(_ data: PenNode.EllipseData) -> Bool {
        [data.innerRadius, data.startAngle].contains { ($0?.literalValue ?? 0) != 0 }
            || (data.sweepAngle?.literalValue).map { $0 < 360 } == true
    }

    /// The strokes a node carries, which this emitter does not draw on its kind.
    func unemittedStrokes(_ stroke: PenFills?) -> [String] {
        PaintRoute(stroke) != .none ? ["strokes"] : []
    }

    /// `shape` in Pen's paint order: painted with the node's fills
    /// (``paintedShape(_:layers:)``), sized by the node's frame and clipped to the shape
    /// when a layer is a view, then its inner shadows and its stroke over them; its outer
    /// shadows, cast by its ``Silhouette``, its background blur and its layer blur last.
    func filledShape(
        _ node: PenNode, shape: Outline, fills: PenFills?, stroke: (any PenStrokable)?, effects: PenEffects?,
        in container: Container, unemitted: [String]
    ) -> SwiftUIViewCode {
        var unemitted = unemitted
        let width = dimension(declaredSizing(node, axis: .width), in: container, empty: true)
        let height = dimension(declaredSizing(node, axis: .height), in: container, empty: true)
        let box = fillBox(width: width, height: height)
        let layers = paintLayers(fills, box: box, of: node.id, unemitted: &unemitted)
        var view = layers.isEmpty ? SwiftUIViewCode(head: "Color.clear") : paintedShape(shape, layers: layers)
        view.modifiers += frameModifiers(width: width, height: height, alignment: .center)
        if needsClip(layers) {
            view = clip(view, to: shape)
        }
        view = view.modified(innerShadows(effects, in: shape, underContent: false))
        let drawn = stroke?.drawn(on: node)
        let outset = drawn.flatMap { FlatOutset(width: width, height: height, stroke: $0) }
        if let drawn {
            let stroked = outset.map { shape.outset($0) } ?? shape
            if var strokeView = strokeView(drawn, shape: stroked, box: box, unemitted: &unemitted) {
                if let outset {
                    strokeView = strokeView.modified(outset.padding)
                }
                view.modifiers.append(SwiftUIViewCode.Modifier(".overlay", content: [strokeView]))
            }
        }
        warnUnemitted(node, unemitted)
        let silhouette = silhouette(of: node, shape: shape, stroke: drawn, box: box, outset: outset)
        return withEffects(view, of: node, effects: effects, fills: fills, silhouette: silhouette)
    }

    /// How far a stroke on a box under a point on either axis is drawn outside it.
    ///
    /// SwiftUI draws no view under a point on either axis, stroke and overlay included, so
    /// the stroke of a line of no height would vanish. Its shape is drawn
    /// ``Outline/outset(_:)`` in a box that negative padding makes the stroke's reach larger
    /// on each flat axis, which leaves the line where it was and its layout box as Pen's.
    struct FlatOutset: Friendly {
        /// The reach on the horizontal axis, zero when the box is wide enough to draw.
        var dx: Double

        /// The reach on the vertical axis, zero when the box is tall enough to draw.
        var dy: Double

        /// The outset for a node of `width` and `height` stroked by `stroke`, or `nil` when
        /// the box is at least a point on both axes (or not fixed on one, which leaves its
        /// size to the layout). The reach is the stroke's widest side, and at least a point.
        init?(width: Dimension, height: Dimension, stroke: any PenStrokable) {
            let flatX = width.fixedValue.map { $0 < 1 } ?? false
            let flatY = height.fixedValue.map { $0 < 1 } ?? false
            guard flatX || flatY else { return nil }
            let reach = max(1, Self.widest(stroke.strokeWidth))
            dx = flatX ? reach : 0
            dy = flatY ? reach : 0
        }

        /// The widest literal side of a stroke width; unset is Pen's 1.
        private static func widest(_ width: PenStrokeWidth?) -> Double {
            switch width {
            case let .uniform(value): value.literalValue ?? 1
            case let .perSide(sides):
                [sides.top, sides.right, sides.bottom, sides.left].compactMap { $0?.literalValue }.max() ?? 1
            case nil: 1
            }
        }

        /// `.penOutset(dx:dy:)`, which draws a shape this far inside the box it is offered.
        var modifier: String {
            let n = SwiftUILiteral.number
            return ".penOutset(dx: \(n(dx)), dy: \(n(dy)))"
        }

        /// The negative padding that grows the stroke's box by the reach on each flat axis.
        var padding: String {
            let n = SwiftUILiteral.number
            if dx > 0, dy > 0, dx == dy { return ".padding(\(n(-dx)))" }
            if dx > 0, dy > 0 { return ".padding(.horizontal, \(n(-dx))).padding(.vertical, \(n(-dy)))" }
            return dx > 0 ? ".padding(.horizontal, \(n(-dx)))" : ".padding(.vertical, \(n(-dy)))"
        }
    }
}
