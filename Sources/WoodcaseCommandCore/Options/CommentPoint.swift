//
//  CommentPoint.swift
//  WoodcaseCommandCore
//

import ArgumentParser

/// The point a comment marks, as `--at x,y` spells it: two numbers and a comma.
///
/// On a node the point is in the node's own coordinates, in points from its top-left
/// corner; on the canvas, in page coordinates. Negative and fractional values are taken
/// as written.
///
/// ```bash
/// woodcase comment design.pen Card/Button --at 12,4 "Too tall?"
/// ```
struct CommentPoint: ExpressibleByArgument {
    /// The horizontal offset.
    var x: Double

    /// The vertical offset.
    var y: Double

    /// Creates a point.
    ///
    /// - Parameters:
    ///   - x: The horizontal offset.
    ///   - y: The vertical offset.
    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Reads `x,y`.
    ///
    /// - Parameter argument: The value as typed.
    init?(argument: String) {
        let parts = argument.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0].trimmingCharacters(in: .whitespaces)), x.isFinite,
              let y = Double(parts[1].trimmingCharacters(in: .whitespaces)), y.isFinite
        else { return nil }
        self.x = x
        self.y = y
    }
}
