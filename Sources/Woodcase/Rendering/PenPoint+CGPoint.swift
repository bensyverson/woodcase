import CoreGraphics

public extension PenPoint {
    /// The point as a CoreGraphics point.
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    /// Creates a point from a CoreGraphics point.
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }
}
