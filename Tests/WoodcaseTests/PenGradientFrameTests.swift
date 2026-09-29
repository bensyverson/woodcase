import CoreGraphics
import Testing
@testable import Woodcase

/// The gradient frame: the map from a gradient's own unit space into its node's box.
///
/// Pen lays every gradient type out in the node's *normalized* box — `center` and
/// `size` are fractions of the box, and `rotation` turns the gradient inside that
/// unit square before the square is stretched to the box. So a 45° gradient on a
/// wide box does not run at 45° on screen.
struct PenGradientFrameTests {
    private let box = CGRect(x: 10, y: 20, width: 400, height: 120)

    private func frame(
        rotation: Double? = nil,
        center: PenFill.PenFillPosition? = nil,
        size: PenFill.PenFillSize? = nil
    ) -> CGAffineTransform {
        PenFill.PenGradientFill(
            gradientType: .linear,
            center: center,
            size: size,
            rotation: rotation.map { .literal($0) }
        ).frameTransform(in: box)
    }

    private func expectClose(_ point: CGPoint, _ x: CGFloat, _ y: CGFloat, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(point.x - x) < 1e-9 && abs(point.y - y) < 1e-9, "\(point) ≠ (\(x), \(y))", sourceLocation: sourceLocation)
    }

    @Test("The frame's origin is the gradient center, at the box center by default")
    func originIsTheCenter() {
        expectClose(CGPoint.zero.applying(frame()), 210, 80)
    }

    @Test("An off-center `center` is a fraction of the box")
    func centerIsAFractionOfTheBox() {
        let t = frame(center: PenFill.PenFillPosition(x: 0.3, y: 0.4))
        expectClose(CGPoint.zero.applying(t), 130, 68)
    }

    @Test("Unrotated, the unit axes span the box")
    func unitAxesSpanTheBox() {
        let t = frame()
        expectClose(CGPoint(x: 0.5, y: 0).applying(t), 410, 80)
        expectClose(CGPoint(x: 0, y: -0.5).applying(t), 210, 20)
    }

    @Test("Rotation 90 turns the gradient's up axis toward the box's left edge")
    func rotationTurnsCounterClockwiseOnScreen() {
        let t = frame(rotation: 90)
        expectClose(CGPoint(x: 0, y: -0.5).applying(t), 10, 80)
    }

    @Test("Rotation happens in the unit square, before the square is stretched to the box")
    func rotationIsInNormalizedSpace() {
        // 45° in the unit square: up (0, -0.5) goes to (-0.354, -0.354) of the square,
        // which on a 400x120 box is (-141.4, -42.4) from the center, not a 45° line.
        let t = frame(rotation: 45)
        let p = CGPoint(x: 0, y: -0.5).applying(t)
        let h = 0.5 * 0.5.squareRoot()
        expectClose(p, 210 - 400 * h, 80 - 120 * h)
    }

    @Test("`size` scales the gradient's own axes before rotation")
    func sizeScalesTheGradientAxes() {
        let t = frame(rotation: 90, size: PenFill.PenFillSize(width: .literal(0.5), height: .literal(0.6)))
        // Up (length 0.6 of the square) rotated to the left: 0.6 * 0.5 * 400 = 120 from the center.
        expectClose(CGPoint(x: 0, y: -0.5).applying(t), 90, 80)
        // Right (length 0.5) rotated to up: 0.5 * 0.5 * 120 = 30 above the center.
        expectClose(CGPoint(x: 0.5, y: 0).applying(t), 210, 50)
    }
}
