//
//  SwiftUIGradient.swift
//  Woodcase
//

import Foundation

/// A .pen gradient fill as SwiftUI: one of SwiftUI's own gradient styles wherever it can
/// say Pen's geometry exactly, and the support file's `PenGradient` view wherever it cannot.
///
/// Pen lays a gradient out in the node's normalised box and then stretches it to the box
/// (``GradientGeometry``). SwiftUI's styles lay out in points, so the two agree only where
/// the stretch changes nothing that matters:
///
/// - a **linear** gradient is fixed by its two stop lines, so start and end points in the
///   box always exist; they are exact on a box of known proportions, and on any box when
///   the gradient is turned by a multiple of 90°;
/// - a **radial** gradient of even size is an `ellipticalGradient`, whose unit circle is
///   stretched to the box exactly as Pen's is;
/// - an **angular** gradient is a `conicGradient` only when the whole map is a similarity
///   — a square box and an even size — since a conic in points is not stretched.
///
/// Every other case (a turned radial ellipse, a conic on an oblong box, a turned linear
/// gradient on a box whose proportions are only known at layout time) is
/// `PenGradient(...)`, a `Canvas` that draws the gradient through Pen's own map. Stops are
/// interpolated in device colour space (`.colorSpace(.device)`), as Pen and Core Graphics
/// do; SwiftUI's default perceptual interpolation measured MAE 10.7 on `render-gradients`.
enum SwiftUIGradient {
    /// A colour's code, and whether it is opaque, or `nil` (reported) when it cannot be
    /// written: how a stop's colour variable is read through the theme.
    typealias ColorCode = (PenValue<String>, inout [String]) -> (code: String, opaque: Bool)?

    /// A length, literal or read through the theme, or `nil` (reported) when it cannot be
    /// written: how a stop's position variable is read through the theme.
    typealias NumberCode = (PenValue<Double>, inout [String]) -> SwiftUINumber?

    /// The gradient's paint, or `nil` when it paints nothing: no stop parses, its size
    /// collapses it, or a stop names a variable `color` or `number` cannot write (reported
    /// in `unemitted`).
    static func content(
        _ fill: PenFill.PenGradientFill, box: FillBox, color: ColorCode, number: NumberCode, unemitted: inout [String]
    ) -> SwiftUIPaintLayer.Content? {
        guard let gradient = gradientLiteral(fill.colors ?? [], color: color, number: number, unemitted: &unemitted) else { return nil }
        let geometry = GradientGeometry(fill)
        guard geometry.width != 0, geometry.height != 0 else { return nil }
        let kind = fill.gradientType ?? .linear
        switch kind {
        case .linear:
            var points: (start: NormalizedPoint, end: NormalizedPoint)?
            if let width = box.width, let height = box.height, width > 0, height > 0 {
                points = linearPoints(geometry, width: width, height: height)
            } else if isQuarterTurn(geometry.rotation) {
                points = (geometry.linearStart, geometry.linearEnd)
            }
            if let points {
                let start = SwiftUILiteral.unitPoint(points.start)
                let end = SwiftUILiteral.unitPoint(points.end)
                return .style(".linearGradient(\(gradient), startPoint: \(start), endPoint: \(end))")
            }
        case .radial:
            if geometry.width == geometry.height {
                let center = SwiftUILiteral.unitPoint(geometry.center)
                let radius = SwiftUILiteral.number(abs(geometry.radiusX))
                return .style(".ellipticalGradient(\(gradient), center: \(center), endRadiusFraction: \(radius))")
            }
        case .angular:
            if isSimilarity(geometry, box: box) {
                let center = SwiftUILiteral.unitPoint(geometry.center)
                let angle = SwiftUILiteral.number(-90 - geometry.rotation)
                return .style(".conicGradient(\(gradient), center: \(center), angle: .degrees(\(angle)))")
            }
        }
        return .view(SwiftUIViewCode(head: penGradient(kind, gradient: gradient, geometry: geometry)))
    }

    /// Start and end points in a `width` × `height` box that draw exactly Pen's linear
    /// gradient.
    ///
    /// Pen's stop lines are the images of the gradient's own horizontal lines; SwiftUI's run
    /// square to the start–end line *in points*. So the start stays on Pen's stop 0, and the
    /// end is the foot of stop 1's line on the perpendicular through it.
    static func linearPoints(
        _ geometry: GradientGeometry, width: Double, height: Double
    ) -> (start: NormalizedPoint, end: NormalizedPoint) {
        let start = geometry.linearStart
        let end = geometry.linearEnd
        let along = geometry.point(NormalizedPoint(x: 1, y: 0.5))
        let line = ((along.x - start.x) * width, (along.y - start.y) * height)
        let length = (line.0 * line.0 + line.1 * line.1).squareRoot()
        guard length > 0 else { return (start, end) }
        let normal = (-line.1 / length, line.0 / length)
        let reach = (end.x - start.x) * width * normal.0 + (end.y - start.y) * height * normal.1
        let foot = NormalizedPoint(
            x: start.x + reach * normal.0 / width,
            y: start.y + reach * normal.1 / height
        )
        return (start, foot)
    }

    /// `Gradient(stops: […]).colorSpace(.device)`, or `nil` when no stop can be written; a
    /// stop's colour variable is read through `color`, its position variable through `number`.
    static func gradientLiteral(
        _ stops: [PenFill.PenGradientStop], color: ColorCode, number: NumberCode, unemitted: inout [String]
    ) -> String? {
        var written: [String] = []
        for stop in stops {
            let code: String
            switch stop.color {
            case .variable:
                guard let read = color(stop.color, &unemitted) else { return nil }
                code = read.code
            case let .literal(hex):
                // The renderer skips a stop it cannot parse; so does this.
                guard let parsed = PenHexColor(hex) else { continue }
                code = SwiftUILiteral.color(parsed)
            }
            guard let location = number(stop.position, &unemitted) else { return nil }
            written.append(".init(color: \(code), location: \(location.code))")
        }
        guard !written.isEmpty else { return nil }
        return "Gradient(stops: [\(written.joined(separator: ", "))]).colorSpace(.device)"
    }

    /// `PenGradient(.kind, gradient, …)`, writing only what differs from Pen's defaults.
    private static func penGradient(_ kind: PenGradientType, gradient: String, geometry: GradientGeometry) -> String {
        var arguments = [".\(kind.rawValue)", gradient]
        if geometry.center != .center {
            arguments.append("center: \(SwiftUILiteral.unitPoint(geometry.center))")
        }
        if geometry.width != 1 { arguments.append("width: \(SwiftUILiteral.number(geometry.width))") }
        if geometry.height != 1 { arguments.append("height: \(SwiftUILiteral.number(geometry.height))") }
        if geometry.rotation != 0 { arguments.append("rotation: \(SwiftUILiteral.number(geometry.rotation))") }
        return "PenGradient(\(arguments.joined(separator: ", ")))"
    }

    /// Whether `degrees` is a whole number of quarter turns.
    private static func isQuarterTurn(_ degrees: Double) -> Bool {
        degrees.truncatingRemainder(dividingBy: 90) == 0
    }

    /// Whether the gradient's whole map onto a box of `box`'s size keeps angles: its two
    /// axes land square to each other and equally long, in points.
    private static func isSimilarity(_ geometry: GradientGeometry, box: FillBox) -> Bool {
        guard let width = box.width, let height = box.height, width > 0, height > 0 else { return false }
        let origin = geometry.point(NormalizedPoint(x: 0, y: 0))
        let xAxis = geometry.point(NormalizedPoint(x: 1, y: 0))
        let yAxis = geometry.point(NormalizedPoint(x: 0, y: 1))
        let u = ((xAxis.x - origin.x) * width, (xAxis.y - origin.y) * height)
        let v = ((yAxis.x - origin.x) * width, (yAxis.y - origin.y) * height)
        let scale = max(u.0 * u.0 + u.1 * u.1, 1e-12)
        let dot = u.0 * v.0 + u.1 * v.1
        let lengths = (u.0 * u.0 + u.1 * u.1) - (v.0 * v.0 + v.1 * v.1)
        return abs(dot) / scale < 1e-9 && abs(lengths) / scale < 1e-9
    }
}
