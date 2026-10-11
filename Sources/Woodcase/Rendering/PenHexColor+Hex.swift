//
//  PenHexColor+Hex.swift
//  Woodcase
//

import Foundation

public extension PenHexColor {
    /// The color as the format spells it: `#RRGGBB` when opaque, `#RRGGBBAA` otherwise,
    /// upper-case. ``init(_:)`` reads it back to the same color.
    var hex: String {
        let channels = alpha == 255 ? [red, green, blue] : [red, green, blue, alpha]
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }
}
