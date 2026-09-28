//
//  PenColorParser.swift
//  Woodcase
//

import CoreGraphics

/// Parses hex color strings from .pen files into `CGColor` values.
///
/// Supports three hex formats:
/// - `#RGB` (3 chars) — expanded to `#RRGGBB`
/// - `#RRGGBB` (6 chars)
/// - `#RRGGBBAA` (8 chars) — last two digits are alpha
///
/// The leading `#` is optional. Returns `nil` for invalid input. The grammar itself is
/// ``PenHexColor``'s, which needs no CoreGraphics; this wraps its result into a `CGColor`.
///
/// ```swift
/// let red = PenColorParser.parse("#FF0000")
/// let halfAlpha = PenColorParser.parse("#FF000080")
/// let shorthand = PenColorParser.parse("#F00")
/// ```
public enum PenColorParser {
    /// Parses a hex color string into a `CGColor`.
    ///
    /// - Parameters:
    ///   - hex: A hex color string, optionally prefixed with `#`.
    ///   - colorSpace: The color space for the returned color. Defaults to sRGB.
    ///     Pass `CGColorSpace(name: CGColorSpace.extendedLinearSRGB)` for HDR rendering.
    /// - Returns: A `CGColor` in the specified color space, or `nil` if the input is invalid.
    public static func parse(
        _ hex: String,
        colorSpace: CGColorSpace? = nil
    ) -> CGColor? {
        guard let color = PenHexColor(hex) else { return nil }
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return CGColor(colorSpace: space, components: color.unitComponents.map { CGFloat($0) })
    }
}
