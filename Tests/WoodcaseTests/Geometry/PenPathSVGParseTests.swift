import Testing
@testable import Woodcase

/// Pins the SVG parse into resolved ``PenPathCommand``s: every command absolute, `H`/`V`
/// as lines, smooth control points reflected, arcs as cubics, and malformed input
/// rejected exactly where the CoreGraphics parser before it rejected it.
struct PenPathSVGParseTests {
    private func commands(_ data: String) -> [PenPathCommand]? {
        PenPath(svg: data)?.commands
    }

    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    // MARK: - Move and line

    @Test("M and L are absolute")
    func moveAndLine() {
        #expect(commands("M 10 20 L 100 200") == [.move(to: pt(10, 20)), .line(to: pt(100, 200))])
    }

    @Test("l is relative to the current point")
    func relativeLine() {
        #expect(commands("M 10 20 l 90 180") == [.move(to: pt(10, 20)), .line(to: pt(100, 200))])
    }

    @Test("A second m is relative to the current point")
    func relativeMove() {
        #expect(commands("m 10 20 m 5 5") == [.move(to: pt(10, 20)), .move(to: pt(15, 25))])
    }

    @Test("H and V become absolute lines")
    func horizontalAndVertical() {
        #expect(commands("M 0 50 H 100 V 80") == [
            .move(to: pt(0, 50)), .line(to: pt(100, 50)), .line(to: pt(100, 80)),
        ])
    }

    @Test("h and v are relative")
    func relativeHorizontalAndVertical() {
        #expect(commands("M 10 10 h 50 v 50") == [
            .move(to: pt(10, 10)), .line(to: pt(60, 10)), .line(to: pt(60, 60)),
        ])
    }

    // MARK: - Cubic curves

    @Test("C is absolute")
    func cubic() {
        #expect(commands("M 0 0 C 25 50 75 50 100 0") == [
            .move(to: pt(0, 0)),
            .cubicCurve(to: pt(100, 0), control1: pt(25, 50), control2: pt(75, 50)),
        ])
    }

    @Test("c offsets every point from the current point")
    func relativeCubic() {
        #expect(commands("M 10 10 c 25 50 75 50 100 0") == [
            .move(to: pt(10, 10)),
            .cubicCurve(to: pt(110, 10), control1: pt(35, 60), control2: pt(85, 60)),
        ])
    }

    @Test("S reflects the previous cubic's second control point", arguments: [
        "M 0 0 C 25 50 75 50 100 0 S 175 -50 200 0",
        "M 0 0 C 25 50 75 50 100 0 s 75 -50 100 0",
    ])
    func smoothCubic(data: String) {
        #expect(commands(data)?.last == .cubicCurve(to: pt(200, 0), control1: pt(125, -50), control2: pt(175, -50)))
    }

    @Test("S after S reflects the previous S's control point")
    func smoothCubicChain() {
        let parsed = commands("M 0 0 C 0 10 10 10 10 0 S 20 -10 20 0 S 30 10 30 0")
        #expect(parsed?.last == .cubicCurve(to: pt(30, 0), control1: pt(20, 10), control2: pt(30, 10)))
    }

    @Test("S after a line takes the current point as its first control point")
    func smoothCubicAfterLine() {
        #expect(commands("M 0 0 L 10 0 S 20 10 30 0")?.last
            == .cubicCurve(to: pt(30, 0), control1: pt(10, 0), control2: pt(20, 10)))
    }

    @Test("S after a quadratic takes the current point, not the quadratic's control point")
    func smoothCubicAfterQuadratic() {
        #expect(commands("M 0 0 Q 50 100 100 0 S 150 -50 200 0")?.last
            == .cubicCurve(to: pt(200, 0), control1: pt(100, 0), control2: pt(150, -50)))
    }

    // MARK: - Quadratic curves

    @Test("Q is absolute")
    func quadratic() {
        #expect(commands("M 0 0 Q 50 100 100 0") == [
            .move(to: pt(0, 0)), .quadCurve(to: pt(100, 0), control: pt(50, 100)),
        ])
    }

    @Test("q is relative")
    func relativeQuadratic() {
        #expect(commands("M 10 10 q 50 100 100 0")?.last == .quadCurve(to: pt(110, 10), control: pt(60, 110)))
    }

    @Test("T reflects the previous quadratic's control point", arguments: [
        "M 0 0 Q 50 100 100 0 T 200 0",
        "M 0 0 Q 50 100 100 0 t 100 0",
    ])
    func smoothQuadratic(data: String) {
        #expect(commands(data)?.last == .quadCurve(to: pt(200, 0), control: pt(150, -100)))
    }

    @Test("T after T reflects the reflected control point")
    func smoothQuadraticChain() {
        #expect(commands("M 0 0 Q 50 100 100 0 T 200 0 T 300 0")?.last
            == .quadCurve(to: pt(300, 0), control: pt(250, 100)))
    }

    @Test("T after a cubic takes the current point, not the cubic's control point")
    func smoothQuadraticAfterCubic() {
        #expect(commands("M 0 0 C 25 50 75 50 100 0 T 200 0")?.last
            == .quadCurve(to: pt(200, 0), control: pt(100, 0)))
    }

    // MARK: - Close and implicit repeats

    @Test("Z returns the current point to the subpath's start")
    func closeResetsCurrentPoint() {
        #expect(commands("M 10 10 L 20 10 Z l 5 5") == [
            .move(to: pt(10, 10)), .line(to: pt(20, 10)), .close, .line(to: pt(15, 15)),
        ])
    }

    @Test("Pairs after M are implicit L")
    func implicitLineAfterMove() {
        #expect(commands("M 0 0 100 100 200 0") == [
            .move(to: pt(0, 0)), .line(to: pt(100, 100)), .line(to: pt(200, 0)),
        ])
    }

    @Test("Pairs after m are implicit l")
    func implicitRelativeLineAfterMove() {
        #expect(commands("m 10 10 5 5") == [.move(to: pt(10, 10)), .line(to: pt(15, 15))])
    }

    @Test("A command's arguments repeat without its letter")
    func implicitRepeat() {
        #expect(commands("M 0 0 L 50 0 100 50") == [
            .move(to: pt(0, 0)), .line(to: pt(50, 0)), .line(to: pt(100, 50)),
        ])
        #expect(commands("M 0 0 C 1 1 2 2 3 3 4 4 5 5 6 6")?.count == 3)
    }

    // MARK: - Number syntax

    @Test("A sign separates numbers")
    func signSeparates() {
        #expect(commands("M10-20L100-200") == [.move(to: pt(10, -20)), .line(to: pt(100, -200))])
        #expect(commands("M0 0l100 0-50 100z") == [
            .move(to: pt(0, 0)), .line(to: pt(100, 0)), .line(to: pt(50, 100)), .close,
        ])
    }

    @Test("A second decimal point starts a number; exponents are read")
    func decimalsAndExponents() {
        #expect(commands("M.5.5L1e1 2E-1") == [.move(to: pt(0.5, 0.5)), .line(to: pt(10, 0.2))])
    }

    // MARK: - Malformed input

    @Test("Input that draws nothing or cannot be read is rejected", arguments: [
        "", "   ", "not a path", "10 10", "M 10", "M 0 0 L 10", "M 0 0 Z 5 5", "M 0 0 X 5 5",
        "M 0 0 A 5 5 0 0",
    ])
    func rejected(data: String) {
        #expect(PenPath(svg: data) == nil)
    }

    @Test("An unknown non-letter character is skipped")
    func unknownCharacterSkipped() {
        #expect(commands("M 0 0 # L 10 10") == [.move(to: pt(0, 0)), .line(to: pt(10, 10))])
    }

    @Test("A lone Z parses to a lone close")
    func loneClose() {
        #expect(commands("Z") == [.close])
    }
}
