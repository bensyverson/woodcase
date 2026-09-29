//
//  PenHexColor.swift
//  Woodcase
//

import Foundation

/// A color as a .pen hex string spells it: four 8-bit channels, sRGB-encoded and
/// unpremultiplied.
///
/// This is the one parser of the format's hex color grammar. It needs only Foundation,
/// so code that must build without CoreGraphics — the mesh core — reads colors through
/// it directly, and ``PenColorParser`` wraps its result into a `CGColor`.
///
/// Three forms are accepted, each with an optional leading `#`:
/// - `#RGB` — each digit doubled, opaque
/// - `#RRGGBB` — opaque
/// - `#RRGGBBAA` — alpha last
///
/// Anything else is refused, including the four-digit `#RGBA` form and a signed number
/// such as `#+12345`.
///
/// ```swift
/// let orange = PenHexColor("#FF8000")   // red 255, green 128, blue 0, alpha 255
/// let clear = PenHexColor("0000FF80")   // alpha 128
/// let refused = PenHexColor("#F008")    // nil
/// ```
public struct PenHexColor: Friendly {
    /// Creates a color from its channels.
    ///
    /// - Parameters:
    ///   - red: The sRGB-encoded red channel.
    ///   - green: The sRGB-encoded green channel.
    ///   - blue: The sRGB-encoded blue channel.
    ///   - alpha: The opacity; the color channels are not multiplied by it.
    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses a `#RGB`, `#RRGGBB` or `#RRGGBBAA` hex string; the `#` is optional.
    ///
    /// - Parameter hex: The color string.
    /// - Returns: The color, or `nil` when the string is not one of the three forms.
    public init?(_ hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        // `UInt64(_:radix:)` alone would take a leading sign, so each digit is checked first.
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt64(digits, radix: 16)
        else { return nil }
        let rgba = digits.count == 8 ? value : (value << 8) | 0xFF
        func channel(_ shift: UInt64) -> UInt8 {
            UInt8((rgba >> shift) & 0xFF)
        }
        self.init(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    /// The sRGB-encoded red channel.
    public var red: UInt8

    /// The sRGB-encoded green channel.
    public var green: UInt8

    /// The sRGB-encoded blue channel.
    public var blue: UInt8

    /// The opacity. The color channels are not multiplied by it.
    public var alpha: UInt8

    /// The four channels as fractions of 255, in red, green, blue, alpha order.
    public var unitComponents: [Double] {
        [red, green, blue, alpha].map { Double($0) / 255 }
    }
}
