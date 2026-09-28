import CoreGraphics

extension PenShapeBuilder {
    /// The rule a node's outline from ``buildPath(for:rect:)`` is filled and clipped with —
    /// ``PenShapeGeometry/fillRule(for:)`` in CoreGraphics' terms.
    static func fillRule(for node: PenNode) -> CGPathFillRule {
        PenShapeGeometry.fillRule(for: node).cgFillRule
    }
}
