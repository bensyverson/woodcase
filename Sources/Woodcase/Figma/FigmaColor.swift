//
//  FigmaColor.swift
//  Woodcase
//

import Foundation

/// A Figma `Color`: four channels from 0 to 1, in sRGB.
struct FigmaColor: Friendly {
    /// Red.
    var red: Double
    /// Green.
    var green: Double
    /// Blue.
    var blue: Double
    /// Alpha.
    var alpha: Double

    /// Reads a `Color` struct, or `nil` when `value` is not one.
    init?(_ value: KiwiValue?) {
        guard let value, let red = value["r"]?.doubleValue, let green = value["g"]?.doubleValue,
              let blue = value["b"]?.doubleValue
        else { return nil }
        self.init(red: red, green: green, blue: blue, alpha: value["a"]?.doubleValue ?? 1)
    }

    /// A color of these channels.
    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The color as Pen's `#RRGGBBAA`, its alpha multiplied by `opacity` — Pen carries a
    /// color fill's opacity only in its alpha.
    func hex(opacity: Double = 1) -> String {
        let channels = [red, green, blue, alpha * opacity].map { channel in
            UInt8((min(max(channel, 0), 1) * 255).rounded())
        }
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }

    /// The color as a ``PenHexColor``, its alpha multiplied by `opacity`.
    func penHexColor(opacity: Double = 1) -> PenHexColor {
        let channels = [red, green, blue, alpha * opacity].map { channel in
            UInt8((min(max(channel, 0), 1) * 255).rounded())
        }
        return PenHexColor(red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3])
    }
}
