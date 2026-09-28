//
//  PenRect+Readable.swift
//  Woodcase
//

import Foundation

public extension PenRect {
    /// The rect as a reader sees it in a tree row or a lint finding: `x,y w×h`.
    ///
    /// Integral values print without a decimal point and everything else to two
    /// places, so a settled rect reads as the round number it almost always is and a
    /// caller comparing two lines is never distracted by `200.0` against `200`.
    var readable: String {
        "\(Self.number(x)),\(Self.number(y)) \(Self.number(width))×\(Self.number(height))"
    }

    /// A number with no decimal point when it is integral, and two places when it is not.
    ///
    /// - Parameter value: The number to spell.
    /// - Returns: The number as a reader would write it; a non-finite value names
    ///   itself rather than printing as a number that does not exist.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "nan" : (value > 0 ? "inf" : "-inf") }
        guard value.rounded() == value, abs(value) < 1e15 else { return String(format: "%.2f", value) }
        return String(Int64(value))
    }
}
