import Foundation
import Testing
@testable import Woodcase

/// A ``PenShapeOutline`` written as SVG path data: every element as the SVG commands that
/// trace what the CoreGraphics call of the same name draws, so an SVG emitter draws the
/// outline the renderer does.
struct PenShapeOutlineSVGTests {
    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    /// Numbers at three decimals, integers bare.
    private func data(_ elements: [PenShapeOutline.Element]) -> String {
        PenShapeOutline(elements: elements).svgPathData { ReactEmitter.cssNumber($0, decimals: 3) }
    }

    private func data(_ shape: PenShapeGeometry.Shape, _ rect: PenRect) throws -> String {
        let outline = try #require(PenShapeGeometry.outline(for: shape, rect: rect))
        return outline.svgPathData { ReactEmitter.cssNumber($0, decimals: 3) }
    }

    private static let box = PenRect(x: 0, y: 0, width: 200, height: 120)

    @Test("Path commands are written as absolute SVG commands")
    func commands() {
        #expect(data([
            .command(.move(to: pt(0, 0))),
            .command(.line(to: pt(10, 0.5))),
            .command(.quadCurve(to: pt(20, 0), control: pt(15, 5))),
            .command(.cubicCurve(to: pt(30, 0), control1: pt(22, 3), control2: pt(28, 3))),
            .command(.close),
        ]) == "M0 0 L10 0.5 Q15 5 20 0 C22 3 28 3 30 0 Z")
    }

    @Test("A whole ellipse is two half arcs from its right-hand point, closed")
    func ellipse() throws {
        #expect(try data(.ellipse(), Self.box) == "M200 60 A100 60 0 1 1 0 60 A100 60 0 1 1 200 60 Z")
    }

    @Test("A pie slice runs from the centre, out along the start angle, round the arc and home")
    func pieSlice() throws {
        #expect(try data(.ellipse(startAngle: 0, sweepAngle: 90), Self.box) == "M100 60 L200 60 A100 60 0 0 0 100 0 Z")
    }

    @Test("An arc donut is the outer arc, a cut to the inner arc, the inner arc back, closed")
    func arcDonut() throws {
        #expect(try data(.ellipse(startAngle: 0, sweepAngle: 90, innerRadius: 0.5), Self.box)
            == "M200 60 A100 60 0 0 0 100 0 L100 30 A50 30 0 0 1 150 60 Z")
    }

    @Test("A sweep past a half turn takes the large arc")
    func largeArc() throws {
        let path = try data(.ellipse(startAngle: 45, sweepAngle: 270, innerRadius: 0.6), Self.box)
        #expect(path.hasPrefix("M170.711 17.574 A100 60 0 1 0 170.711 102.426 L142.426 85.456 A60 36 0 1 1 142.426 34.544 Z"), "\(path)")
    }

    @Test("A negative sweep turns the other way")
    func negativeSweep() throws {
        #expect(try data(.ellipse(startAngle: 90, sweepAngle: -90), Self.box) == "M100 60 L100 0 A100 60 0 0 1 200 60 Z")
    }

    @Test("A ring is two whole ellipses")
    func ring() throws {
        #expect(try data(.ellipse(innerRadius: 0.5), Self.box)
            == "M200 60 A100 60 0 1 1 0 60 A100 60 0 1 1 200 60 Z M150 60 A50 30 0 1 1 50 60 A50 30 0 1 1 150 60 Z")
    }

    @Test("A tangent arc draws a line to its first tangent point and a circular arc to its second")
    func tangentArc() {
        #expect(data([
            .command(.move(to: pt(0, 0))),
            .tangentArc(tangent1End: pt(100, 0), tangent2End: pt(100, 50), radius: 10),
        ]) == "M0 0 L90 0 A10 10 0 0 1 100 10")
    }

    @Test("A tangent arc turning the other way sweeps the other way")
    func tangentArcCounterClockwise() {
        #expect(data([
            .command(.move(to: pt(0, 50))),
            .tangentArc(tangent1End: pt(100, 50), tangent2End: pt(100, 0), radius: 10),
        ]) == "M0 50 L90 50 A10 10 0 0 0 100 40")
    }

    @Test("A rect is a closed four-sided subpath")
    func rect() {
        #expect(data([.rect(PenRect(x: 1, y: 2, width: 10, height: 20))]) == "M1 2 L11 2 L11 22 L1 22 Z")
    }

    @Test("A rounded rect traces each edge and each corner arc, clockwise from the top-left")
    func roundedRect() {
        #expect(data([.roundedRect(PenRect(x: 0, y: 0, width: 100, height: 40), cornerRadius: 10)])
            == "M10 0 L90 0 A10 10 0 0 1 100 10 L100 30 A10 10 0 0 1 90 40 L10 40 A10 10 0 0 1 0 30 L0 10 A10 10 0 0 1 10 0 Z")
    }
}
