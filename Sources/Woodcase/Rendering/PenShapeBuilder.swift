import CoreGraphics

/// Builds `CGPath` objects for each .pen node shape type.
///
/// The CoreGraphics face of ``PenShapeGeometry``, which decides every outline without
/// CoreGraphics; this only draws it.
enum PenShapeBuilder {
    /// Builds a `CGPath` for the given shape type within the given rect.
    ///
    /// - Parameters:
    ///   - shape: The shape type and its parameters.
    ///   - rect: The bounding rectangle for the shape.
    ///   - cornerRadius: Optional corner radii, for rectangles.
    /// - Returns: A `CGPath`, or `nil` if the shape cannot be built.
    static func buildPath(
        for shape: PenShapeGeometry.Shape,
        rect: PenRect,
        cornerRadius: PenCornerRadius.Corners? = nil
    ) -> CGPath? {
        PenShapeGeometry.outline(for: shape, rect: rect, cornerRadius: cornerRadius)?.cgPath
    }

    /// Builds a `CGPath` from a `PenNode`, or `nil` for a node kind with no shape.
    static func buildPath(for node: PenNode, rect: PenRect) -> CGPath? {
        PenShapeGeometry.outline(for: node, rect: rect)?.cgPath
    }
}
