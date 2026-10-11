//
//  PenHexColor+Luminance.swift
//  Woodcase
//

import Foundation

public extension PenHexColor {
    /// The color's relative luminance, 0 for black to 1 for white, as WCAG defines it:
    /// each sRGB channel linearized, then weighted 0.2126, 0.7152 and 0.0722. Alpha is
    /// ignored.
    var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// This color moved toward another by a fraction, channel by channel in sRGB.
    ///
    /// - Parameters:
    ///   - other: The color to move toward.
    ///   - fraction: 0 keeps this color, 1 gives `other`; clamped to that range.
    /// - Returns: The mix, each channel rounded to the nearest step.
    func mixed(toward other: PenHexColor, by fraction: Double) -> PenHexColor {
        let amount = min(1, max(0, fraction))
        func mix(_ from: UInt8, _ to: UInt8) -> UInt8 {
            UInt8((Double(from) + (Double(to) - Double(from)) * amount).rounded())
        }
        return PenHexColor(
            red: mix(red, other.red), green: mix(green, other.green),
            blue: mix(blue, other.blue), alpha: mix(alpha, other.alpha)
        )
    }
}
