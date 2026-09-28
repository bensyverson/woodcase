import CoreGraphics
import Testing
@testable import Woodcase

/// Pins the seam between the geometry model and CoreGraphics: a ``PenPath`` becomes a
/// `CGPath` element for element, and a `CGPath` reads back as the same commands.
struct PenPathCGPathTests {
    private static let commands: [PenPathCommand] = [
        .move(to: PenPoint(x: 1, y: 2)),
        .line(to: PenPoint(x: 3, y: 4)),
        .quadCurve(to: PenPoint(x: 5, y: 6), control: PenPoint(x: 7, y: 8)),
        .cubicCurve(to: PenPoint(x: 9, y: 10), control1: PenPoint(x: 11, y: 12), control2: PenPoint(x: 13, y: 14)),
        .close,
    ]

    @Test("A path's commands survive the trip through CGPath")
    func roundTrip() {
        let path = PenPath(commands: Self.commands)
        #expect(PenPath(path.cgPath) == path)
    }

    @Test("A CGPath reads back as its elements")
    func readsCGPath() {
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 1, y: 2))
        cgPath.addLine(to: CGPoint(x: 3, y: 4))
        cgPath.addQuadCurve(to: CGPoint(x: 5, y: 6), control: CGPoint(x: 7, y: 8))
        cgPath.addCurve(to: CGPoint(x: 9, y: 10), control1: CGPoint(x: 11, y: 12), control2: CGPoint(x: 13, y: 14))
        cgPath.closeSubpath()
        #expect(PenPath(cgPath).commands == Self.commands)
    }

    @Test("An outline's primitives draw what CoreGraphics' own primitives draw")
    func outlinePrimitives() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        let penRect = PenRect(x: 0, y: 0, width: 100, height: 50)
        #expect(PenShapeOutline(elements: [.rect(penRect)]).cgPath == CGPath(rect: rect, transform: nil))
        #expect(PenShapeOutline(elements: [.ellipse(in: penRect)]).cgPath == CGPath(ellipseIn: rect, transform: nil))
        #expect(PenShapeOutline(elements: [.roundedRect(penRect, cornerRadius: 10)]).cgPath
            == CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
    }
}
