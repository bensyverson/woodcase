//
//  ShotCommand+Scale.swift
//  WoodcaseCommandCore
//

import Foundation

extension Shot {
    /// `min(1, maxPoints / longestSide)`: never enlarges, shrinks only past `maxPoints`.
    ///
    /// - Parameters:
    ///   - longestSide: The longer of the node's layout width and height, in points.
    ///   - maxPoints: The `--max` value.
    /// - Returns: The scale factor to render at.
    static func effectiveScale(longestSide: Double, maxPoints: Double) -> Double {
        guard longestSide > 0 else { return 1 }
        return min(1, maxPoints / longestSide)
    }
}
