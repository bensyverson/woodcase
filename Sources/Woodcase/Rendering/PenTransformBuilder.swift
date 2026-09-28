import CoreGraphics

/// Builds `CGAffineTransform` from a node's rotation and flip properties.
///
/// Transform order: translate to pivot → rotate → flip X/Y → translate back from pivot.
/// The pivot is the centre of the node's unturned box; see ``buildTransform(for:rect:)``.
///
/// Public because it is the oracle for downstream renderers: RapidPro's
/// `RenderNodeProducer` must place a node exactly where this transform does, and
/// its tests assert that against this function rather than a hand-written mirror.
public enum PenTransformBuilder {
    /// Builds a transform for the given node within its layout rect.
    ///
    /// The rect should be zero-origin (position is handled separately by the renderer).
    /// Returns `.identity` if the node has no rotation or flip properties.
    ///
    /// Rotation and flip pivot at the centre of the node's unturned box, `rect`. Pen turns
    /// a node placed by its own `x`/`y` about that anchor, not its centre; the renderer
    /// draws the same picture because the layout has already moved the node's turned bounds
    /// to where the anchor turn puts them (``PenLayoutEngine/freeRect(of:x:y:box:)``), and
    /// `rect` is the unturned box centred in them. A `group` is no exception: its box is
    /// its children's union (``PenLayoutEngine/unturnedBox(of:rect:layoutRects:)``),
    /// which the renderer centres in the group's rect in the same way before it moves to the
    /// group's anchor, the origin its children are placed from. See `PenRendering.md`,
    /// *Transforms*.
    public static func buildTransform(for node: PenNode, rect: PenRect) -> CGAffineTransform {
        let rotation = node.common.rotation?.literalValue ?? 0
        let flipX = node.common.flipX?.literalValue ?? false
        let flipY = node.common.flipY?.literalValue ?? false

        guard rotation != 0 || flipX || flipY else {
            return .identity
        }

        let pivotX = CGFloat(rect.width) / 2
        let pivotY = CGFloat(rect.height) / 2

        var transform = CGAffineTransform.identity

        // Translate to pivot
        transform = transform.translatedBy(x: pivotX, y: pivotY)

        // Rotate: .pen uses counter-clockwise degrees
        // In our flipped coordinate system (y-down), a CCW rotation in math
        // appears CW on screen, which matches .pen's convention.
        if rotation != 0 {
            let radians = -CGFloat(rotation) * .pi / 180
            transform = transform.rotated(by: radians)
        }

        // Flip
        if flipX {
            transform = transform.scaledBy(x: -1, y: 1)
        }
        if flipY {
            transform = transform.scaledBy(x: 1, y: -1)
        }

        // Translate back from pivot
        transform = transform.translatedBy(x: -pivotX, y: -pivotY)

        return transform
    }
}
