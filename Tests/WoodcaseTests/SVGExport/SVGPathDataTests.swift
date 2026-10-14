import CoreGraphics
import Testing
@testable import Woodcase

/// A `CGPath` written as SVG path data: one command per element, numbers trimmed.
struct SVGPathDataTests {
    @Test("A rectangle writes move, lines and close")
    func rectangle() {
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 20), transform: nil)
        #expect(path.svgPathData == "M0 0L10 0L10 20L0 20Z")
    }

    @Test("Curves write C and Q with every control point")
    func curves() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1, y: 2))
        path.addCurve(to: CGPoint(x: 7, y: 8), control1: CGPoint(x: 3, y: 4), control2: CGPoint(x: 5, y: 6))
        path.addQuadCurve(to: CGPoint(x: 11, y: 12), control: CGPoint(x: 9, y: 10))
        #expect(path.svgPathData == "M1 2C3 4 5 6 7 8Q9 10 11 12")
    }

    @Test("Fractions keep four places and drop trailing zeros; negatives keep their sign")
    func numbers() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: -1.123456))
        path.addLine(to: CGPoint(x: 1.0 / 3.0, y: 2.10))
        #expect(path.svgPathData == "M0.5 -1.1235L0.3333 2.1")
    }

    @Test("An empty path writes nothing")
    func empty() {
        #expect(CGMutablePath().svgPathData.isEmpty)
    }
}
