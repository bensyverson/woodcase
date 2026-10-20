//
//  FigmaPoint.swift
//  Woodcase
//

/// A point or offset in a Figma blob's coordinate space.
///
/// Blobs store single-precision floats; each is widened to `Double` exactly, so a point
/// compares equal to the float it was read from.
public struct FigmaPoint: Friendly {
    /// The horizontal coordinate.
    public var x: Double
    /// The vertical coordinate; Figma's y grows downward, except in glyph outlines.
    public var y: Double

    /// The origin, and the zero offset.
    public static let zero = FigmaPoint(x: 0, y: 0)

    /// A point at `x`, `y`.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// `lhs` moved by the offset `rhs`.
    public static func + (lhs: FigmaPoint, rhs: FigmaPoint) -> FigmaPoint {
        FigmaPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}
