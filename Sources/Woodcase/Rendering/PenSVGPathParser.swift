import CoreGraphics

/// Parses SVG path data strings into `CGPath` objects.
///
/// The CoreGraphics face of ``PenPath/init(svg:)``, which does the parse without
/// CoreGraphics: every SVG path command, with arcs converted to cubic Béziers per the
/// W3C SVG specification.
public enum PenSVGPathParser {
    /// Parses an SVG path data string into a `CGPath`.
    ///
    /// - Parameters:
    ///   - pathData: An SVG path data string (e.g. `"M 0 0 L 100 100"`).
    ///   - fillRule: Unused: a `CGPath` carries no fill rule, which is applied when it is filled.
    /// - Returns: A `CGPath` if the path data is valid and non-empty, otherwise `nil`.
    public static func parse(_ pathData: String, fillRule _: PenFillRule = .nonzero) -> CGPath? {
        PenPath(svg: pathData)?.cgPath
    }
}
