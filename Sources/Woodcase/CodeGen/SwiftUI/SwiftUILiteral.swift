//
//  SwiftUILiteral.swift
//  Woodcase
//

import Foundation

/// Swift source spellings of the values the SwiftUI emitter writes: numbers, strings and
/// colors.
enum SwiftUILiteral {
    /// A number as a reader would write it: `80`, `0.5`, `-12`.
    ///
    /// A whole number drops its fraction; anything else is Swift's shortest round-trip
    /// spelling, so the emitted value is exactly the document's.
    static func number(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    /// A string literal, with quotes, backslashes and control characters escaped.
    static func string(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case "\0": escaped += "\\0"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return "\"\(escaped)\""
    }

    /// A color through the support file's `Color(hex:opacity:)`: `Color(hex: 0xE0E0E0)`,
    /// with the opacity only when the color is not opaque.
    static func color(_ color: PenHexColor) -> String {
        let hex = String(format: "0x%02X%02X%02X", color.red, color.green, color.blue)
        guard color.alpha < 255 else { return "Color(hex: \(hex))" }
        let opacity = (Double(color.alpha) / 255 * 1000).rounded() / 1000
        return "Color(hex: \(hex), opacity: \(number(opacity)))"
    }
}
