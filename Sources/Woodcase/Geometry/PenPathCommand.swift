import Foundation

/// One fully resolved drawing command of a ``PenPath``.
///
/// Every coordinate is absolute. Parsing SVG path data resolves everything a target would
/// otherwise have to re-derive: relative commands are made absolute, `H`/`V` become lines,
/// the reflected control point of `S`/`T` is written out, and every elliptical arc is
/// converted to cubic Béziers. So each case maps one-to-one onto a CoreGraphics call and
/// onto a SwiftUI `Path` call of the same name.
public enum PenPathCommand: Friendly {
    /// Starts a new subpath at a point.
    case move(to: PenPoint)
    /// A straight line from the current point.
    case line(to: PenPoint)
    /// A quadratic Bézier from the current point.
    case quadCurve(to: PenPoint, control: PenPoint)
    /// A cubic Bézier from the current point.
    case cubicCurve(to: PenPoint, control1: PenPoint, control2: PenPoint)
    /// Closes the current subpath with a straight line back to its start.
    case close

    /// The same command with every point it names — endpoint and control points — passed
    /// through `transform`.
    public func mappingPoints(_ transform: (PenPoint) -> PenPoint) -> PenPathCommand {
        switch self {
        case let .move(to):
            .move(to: transform(to))
        case let .line(to):
            .line(to: transform(to))
        case let .quadCurve(to, control):
            .quadCurve(to: transform(to), control: transform(control))
        case let .cubicCurve(to, control1, control2):
            .cubicCurve(to: transform(to), control1: transform(control1), control2: transform(control2))
        case .close:
            .close
        }
    }
}
