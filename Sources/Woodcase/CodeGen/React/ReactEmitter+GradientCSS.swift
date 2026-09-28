//
//  ReactEmitter+GradientCSS.swift
//  Woodcase
//

extension ReactEmitter {
    /// A gradient's stops as CSS colours and positions (0…1).
    typealias GradientStops = [(color: String, position: Double)]

    /// The CSS for a gradient fill laid out over the node's box, drawn on an element that
    /// reaches `outsets` past that box on each side (a stroke overlay; zero for the node's
    /// own background or its text).
    ///
    /// Each gradient type states Pen's geometry (``GradientGeometry``) in CSS its own way:
    /// a linear gradient on a tile whose diagonal carries the slant
    /// (``cssLinearGradient(_:stops:box:outsets:)``), a radial one as an axis-aligned CSS
    /// ellipse or, turned off the axes, an SVG paint server
    /// (``cssRadialGradient(_:stops:box:outsets:)``), and an angular one as a conic gradient
    /// turned to Pen's start and bent to a stretched box's bearings
    /// (``cssConicGradient(_:stops:box:outsets:)``). Pen *pads* a gradient beyond the node's
    /// box — an outer stroke's outer band shows the end colours
    /// (`project/2026-09-26-text-and-stroke-fills.md`, finding 2) — and so does each of these.
    ///
    /// - Parameters:
    ///   - gradient: The gradient fill.
    ///   - box: The node's box: its proportions bend an angular gradient (a box with a side
    ///     that is not fixed counts as square), and its size bounds how far a tile must grow
    ///     to reach a stroke's outer edge. Linear and radial gradients need neither.
    ///   - outsets: How far the painted element reaches past the node's box on each side.
    /// - Returns: The layer, or `nil` when the gradient has no stops or collapses.
    static func cssGradient(
        _ gradient: PenFill.PenGradientFill,
        box: FillBox,
        outsets: EdgeLengths = EdgeLengths(all: .zero)
    ) -> CSSGradient? {
        guard let stops = gradientStops(gradient) else { return nil }
        switch gradient.gradientType {
        case .linear, nil:
            return cssLinearGradient(GradientGeometry(gradient), stops: stops, box: box, outsets: outsets)
        case .radial:
            return cssRadialGradient(GradientGeometry(gradient), stops: stops, box: box, outsets: outsets)
        case .angular:
            return cssConicGradient(GradientGeometry(gradient), stops: stops, box: box, outsets: outsets)
        }
    }

    /// The gradient fill as a `background` shorthand layer over the element's own box.
    static func emitGradientCSS(_ gradient: PenFill.PenGradientFill, box: FillBox) -> String? {
        cssGradient(gradient, box: box)?.backgroundLayer
    }

    /// A gradient's stops as CSS colours and positions (0…1), or `nil` when it has none.
    /// The fill's opacity is baked into each colour's alpha, as Pen's own HTML export does.
    static func gradientStops(_ gradient: PenFill.PenGradientFill) -> GradientStops? {
        guard let colors = gradient.colors, !colors.isEmpty else { return nil }
        let opacity = gradient.opacity?.literalValue ?? 1
        return colors.map { stop in
            let color: String = switch stop.color {
            case let .literal(c): c
            case let .variable(n): "var(--\(n))"
            }
            return (cssColor(color, opacity: opacity), stop.position.literalValue ?? 0)
        }
    }

    /// A fraction as a CSS percentage, to a thousandth of a percent: `0.25` is `25%`.
    static func cssPercent(_ fraction: Double) -> String {
        "\(cssNumber(fraction * 100, decimals: 3))%"
    }
}
