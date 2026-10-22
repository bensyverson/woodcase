//
//  PenScaleRounding.swift
//  Woodcase
//

import Foundation

/// How finely a proportional scale keeps the values it writes.
///
/// A scale (``ScaleCapture``, ``EditPlanner/planScale(nodeIDs:by:anchor:in:layout:)``) keeps a
/// length to a hundredth of a point and a factor — a note's look scale, `note.scale` — to four
/// decimals, and never rounds a value that was not zero to nothing. An editor that sizes a
/// node some other way and must write what a scale writes (Penumbra's note resize scales the
/// look and the letter spacing with the box) rounds through these, so the rule lives in one
/// place.
///
/// ```swift
/// PenScaleRounding.length(1.5, by: 1.25)        // 1.88
/// PenScaleRounding.factor(1, by: 20.0 / 13.0)   // 1.5385
/// ```
public enum PenScaleRounding {
    /// How finely a scaled length is kept: hundredths of a point.
    public static let lengthPrecision = 100.0

    /// How finely a scaled factor is kept: four decimals, finer than a length's hundredth,
    /// so a note's look scale tracks its type size (20 / 13 is 1.5385).
    public static let factorPrecision = 10000.0

    /// A length multiplied by `factor` and kept to a hundredth of a point.
    ///
    /// A length that was not zero stays off zero, on its own side of it: a hundredth, or
    /// minus a hundredth.
    ///
    /// - Parameters:
    ///   - length: The length before the scale, in points.
    ///   - factor: The scale factor.
    /// - Returns: The scaled length.
    public static func length(_ length: Double, by factor: Double) -> Double {
        let rounded = (length * factor * lengthPrecision).rounded() / lengthPrecision
        if rounded == 0, length != 0 { return length > 0 ? 1 / lengthPrecision : -1 / lengthPrecision }
        return rounded
    }

    /// A factor multiplied by `factor` and kept to four decimals.
    ///
    /// A value above zero stays above zero: the smallest it rounds to is a ten-thousandth.
    ///
    /// - Parameters:
    ///   - value: The factor before the scale, such as a note's look scale (1 when unset).
    ///   - factor: The scale factor.
    /// - Returns: The scaled factor.
    public static func factor(_ value: Double, by factor: Double) -> Double {
        let scaled = (value * factor * factorPrecision).rounded() / factorPrecision
        return scaled == 0 && value > 0 ? 1 / factorPrecision : scaled
    }
}
