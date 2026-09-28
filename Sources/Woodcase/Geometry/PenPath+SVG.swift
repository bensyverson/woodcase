import Foundation

public extension PenPath {
    /// Parses SVG path data into resolved commands.
    ///
    /// Supports every SVG path command — M/m, L/l, H/h, V/v, C/c, S/s, Q/q, T/t, A/a, Z/z —
    /// with implicit repeats and compact number syntax. Arcs become cubic Béziers.
    ///
    /// - Parameter pathData: SVG path data, such as `"M 0 0 L 100 100"`.
    /// - Returns: The path, or `nil` when the data is empty, starts with a number, names a
    ///   command SVG does not define, or runs out of arguments mid-command.
    init?(svg pathData: String) {
        var reader = PenSVGPathReader(tokens: PenSVGPathTokenizer.tokenize(pathData))
        guard let commands = reader.read() else { return nil }
        self.init(commands: commands)
    }
}
