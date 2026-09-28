import CoreGraphics

public extension CGPath {
    /// The tight visual bounding box, from the Bézier curves' analytic extrema.
    ///
    /// Unlike `boundingBox`, which includes control points in its bounds (inflating the box
    /// for curves whose control points extend beyond the rendered curve), this is
    /// ``PenPath/tightBounds`` of the path's elements; `CGRect.null` for a path with no points.
    var tightBoundingBox: CGRect {
        PenPath(self).tightBounds?.cgRect ?? .null
    }
}
