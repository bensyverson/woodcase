import Foundation

/// Reads tokenized SVG path data into resolved ``PenPathCommand``s.
///
/// Holds the state SVG's relative and smooth commands depend on: the current point, the
/// start of the current subpath, and the last control point of a preceding curve.
struct PenSVGPathReader: Friendly {
    private typealias Token = PenSVGPathTokenizer.Token

    private var tokens: [Token]
    private var index = 0
    private var current = PenPoint.zero
    private var subpathStart = PenPoint.zero
    /// The second control point of the previous command when it was `C` or `S`; `S` reflects it.
    private var cubicControl: PenPoint?
    /// The control point of the previous command when it was `Q` or `T`; `T` reflects it.
    private var quadControl: PenPoint?
    private var commands: [PenPathCommand] = []

    /// Creates a reader over the tokens of one path's data.
    init(tokens: [PenSVGPathTokenizer.Token]) {
        self.tokens = tokens
    }

    /// Reads every token into commands.
    ///
    /// - Returns: The commands, or `nil` when the data is empty, starts with a number,
    ///   names a command SVG does not define, or runs out of arguments mid-command.
    mutating func read() -> [PenPathCommand]? {
        guard !tokens.isEmpty else { return nil }
        var lastCommand: Character?

        while index < tokens.count {
            guard case let .command(letter) = tokens[index], let command = letter.first else {
                // Numbers with no letter repeat the previous command; after M they are lines.
                guard let last = lastCommand, last != "Z", last != "z" else { return nil }
                let implicit: Character = last == "M" ? "L" : last == "m" ? "l" : last
                guard execute(implicit) else { return nil }
                lastCommand = implicit
                continue
            }
            index += 1
            guard execute(command) else { return nil }
            lastCommand = command
        }
        return commands
    }

    // MARK: - Commands

    /// Executes one command, reading its arguments. Returns `false` when they are missing
    /// or the command is unknown.
    private mutating func execute(_ command: Character) -> Bool {
        let relative = command.isLowercase
        func absolute(_ point: PenPoint) -> PenPoint {
            relative ? PenPoint(x: current.x + point.x, y: current.y + point.y) : point
        }

        switch command.uppercased() {
        case "Z":
            commands.append(.close)
            finish(at: subpathStart)
        case "M":
            guard let point = readPoint() else { return false }
            let to = absolute(point)
            commands.append(.move(to: to))
            subpathStart = to
            finish(at: to)
        case "L":
            guard let point = readPoint() else { return false }
            let to = absolute(point)
            commands.append(.line(to: to))
            finish(at: to)
        case "H":
            guard let x = readNumber() else { return false }
            let to = PenPoint(x: relative ? current.x + x : x, y: current.y)
            commands.append(.line(to: to))
            finish(at: to)
        case "V":
            guard let y = readNumber() else { return false }
            let to = PenPoint(x: current.x, y: relative ? current.y + y : y)
            commands.append(.line(to: to))
            finish(at: to)
        case "C":
            guard let c1 = readPoint(), let c2 = readPoint(), let to = readPoint() else { return false }
            cubic(to: absolute(to), control1: absolute(c1), control2: absolute(c2))
        case "S":
            guard let c2 = readPoint(), let to = readPoint() else { return false }
            let c1 = cubicControl.map(reflected) ?? current
            cubic(to: absolute(to), control1: c1, control2: absolute(c2))
        case "Q":
            guard let control = readPoint(), let to = readPoint() else { return false }
            quad(to: absolute(to), control: absolute(control))
        case "T":
            guard let to = readPoint() else { return false }
            quad(to: absolute(to), control: quadControl.map(reflected) ?? current)
        case "A":
            guard let rx = readNumber(), let ry = readNumber(), let rotation = readNumber(),
                  let largeArc = readFlag(), let sweep = readFlag(), let point = readPoint()
            else { return false }
            let to = absolute(point)
            let arc = PenSVGArc(
                from: current, to: to, radiusX: abs(rx), radiusY: abs(ry),
                rotation: rotation, largeArc: largeArc, sweep: sweep
            )
            commands.append(contentsOf: arc.commands)
            finish(at: to)
        default:
            return false
        }
        return true
    }

    private mutating func cubic(to: PenPoint, control1: PenPoint, control2: PenPoint) {
        commands.append(.cubicCurve(to: to, control1: control1, control2: control2))
        current = to
        cubicControl = control2
        quadControl = nil
    }

    private mutating func quad(to: PenPoint, control: PenPoint) {
        commands.append(.quadCurve(to: to, control: control))
        current = to
        quadControl = control
        cubicControl = nil
    }

    /// Moves the current point after a command that leaves no control point to reflect.
    private mutating func finish(at point: PenPoint) {
        current = point
        cubicControl = nil
        quadControl = nil
    }

    /// A control point reflected through the current point.
    private func reflected(_ control: PenPoint) -> PenPoint {
        PenPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    // MARK: - Arguments

    private mutating func readNumber() -> Double? {
        guard index < tokens.count, case let .number(value, _) = tokens[index] else { return nil }
        index += 1
        return value
    }

    private mutating func readPoint() -> PenPoint? {
        guard let x = readNumber(), let y = readNumber() else { return nil }
        return PenPoint(x: x, y: y)
    }

    /// Reads an arc flag. SVG writes a flag as one character, so `01` is two flags and
    /// `1100` is a flag followed by `100`: the rest of such a run is put back as the next number.
    /// Any other number is read leniently, as nonzero or not.
    private mutating func readFlag() -> Bool? {
        guard index < tokens.count, case let .number(value, text) = tokens[index] else { return nil }
        guard text.count > 1, let first = text.first, first == "0" || first == "1" else {
            index += 1
            return value != 0
        }
        let rest = String(text.dropFirst())
        guard let restValue = Double(rest) else { return nil }
        tokens[index] = .number(restValue, text: rest)
        return first == "1"
    }
}
