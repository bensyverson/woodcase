import Foundation

/// A point in a node's drawing space, in points, y growing downward.
///
/// The geometry layer's own point type, so path and shape geometry can be computed —
/// and emitted as code — without CoreGraphics. The renderer converts it with `cgPoint`.
public struct PenPoint: Friendly {
    /// The horizontal coordinate.
    public var x: Double
    /// The vertical coordinate, growing downward.
    public var y: Double

    /// Creates a point from its two coordinates.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The origin, `(0, 0)`.
    public static let zero = PenPoint(x: 0, y: 0)
}
