import Foundation

/// The outline of a node's shape, as drawing elements independent of any graphics framework.
///
/// ``PenShapeGeometry`` computes it from a node and its box. Beyond the resolved
/// ``PenPathCommand``s of an SVG path, a shape uses a few primitives that both CoreGraphics
/// and SwiftUI's `Path` provide under the same name and with the same semantics, so a
/// renderer and a code emitter each map every element one-to-one and draw the same outline.
struct PenShapeOutline: Friendly {
    /// One drawing element of an outline.
    enum Element: Friendly {
        /// A resolved path command.
        case command(PenPathCommand)
        /// A circular arc tangent to the line from the current point to `tangent1End` and to
        /// the line from `tangent1End` to `tangent2End`, preceded by a straight line to the
        /// arc's start — `addArc(tangent1End:tangent2End:radius:)`.
        case tangentArc(tangent1End: PenPoint, tangent2End: PenPoint, radius: Double)
        /// An arc of the ellipse centred on `center` with radii `radiusX` × `radiusY`, from
        /// `startAngle` to `endAngle` (radians, measured on the unit circle before the
        /// ellipse's scale, in the y-down drawing space), preceded by a straight line from
        /// the current point to its start when there is one. `clockwise` has the meaning of
        /// the flag of `addArc(center:radius:startAngle:endAngle:clockwise:transform:)`,
        /// which draws it as a unit-circle arc scaled by the radii and moved to the centre.
        case ellipticalArc(
            center: PenPoint,
            radiusX: Double,
            radiusY: Double,
            startAngle: Double,
            endAngle: Double,
            clockwise: Bool
        )
        /// A closed rectangle subpath — `addRect(_:)`.
        case rect(PenRect)
        /// A closed rectangle subpath with circular corners of one radius —
        /// `addRoundedRect(in:cornerWidth:cornerHeight:)` with both set to `cornerRadius`.
        case roundedRect(PenRect, cornerRadius: Double)
        /// A closed ellipse subpath inscribed in a rectangle — `addEllipse(in:)`.
        case ellipse(in: PenRect)
    }

    /// The elements, in drawing order.
    var elements: [Element]
}
