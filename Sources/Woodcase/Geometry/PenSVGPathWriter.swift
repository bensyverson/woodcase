import Foundation

/// Writes absolute SVG path commands, tracking the current point and the start of the current
/// subpath, which later commands — a closing `Z`, an outline's tangent arc — depend on.
///
/// ``PenPath/svgPathData`` writes a path's resolved commands through it; ``PenShapeOutline``
/// adds its own primitives on top (`PenSVGPathWriter+OutlineElements.swift`).
struct PenSVGPathWriter {
    /// How a coordinate is written.
    let number: (Double) -> String
    /// The commands written so far.
    var commands: [String] = []
    /// The current point, `nil` before the first command.
    var current: PenPoint?
    /// Where the current subpath started, which a close returns to.
    var subpathStart: PenPoint?

    /// The commands separated by spaces, e.g. `M0 0 L10 0 Z`.
    var pathData: String {
        commands.joined(separator: " ")
    }

    /// Writes a number in the shortest form that reads back as the same `Double`: whole
    /// numbers bare, negative zero as `0`, and Swift's round-tripping description otherwise
    /// (which uses an exponent, `1e-07`, where SVG's number grammar accepts one).
    ///
    /// A non-finite value has no SVG spelling; it is written as Swift describes it and the
    /// path data will not parse.
    static func exactNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        let text = "\(value)"
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// Appends the command for one resolved path command.
    mutating func write(_ command: PenPathCommand) {
        switch command {
        case let .move(to):
            move(to)
        case let .line(to):
            line(to)
        case let .quadCurve(to, control):
            commands.append("Q\(pair(control)) \(pair(to))")
            current = to
        case let .cubicCurve(to, control1, control2):
            commands.append("C\(pair(control1)) \(pair(control2)) \(pair(to))")
            current = to
        case .close:
            close()
        }
    }

    /// A point's two coordinates, separated by a space.
    func pair(_ point: PenPoint) -> String {
        "\(number(point.x)) \(number(point.y))"
    }

    /// Starts a subpath at `point`.
    mutating func move(_ point: PenPoint) {
        commands.append("M\(pair(point))")
        current = point
        subpathStart = point
    }

    /// A straight line to `point`.
    mutating func line(_ point: PenPoint) {
        commands.append("L\(pair(point))")
        current = point
    }

    /// Closes the subpath, returning the current point to its start.
    mutating func close() {
        commands.append("Z")
        current = subpathStart
    }
}
