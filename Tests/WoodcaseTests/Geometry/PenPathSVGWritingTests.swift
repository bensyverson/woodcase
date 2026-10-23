import Foundation
import Testing
@testable import Woodcase

/// A ``PenPath`` written back out as SVG path data: every command absolute, every number
/// in the shortest form that reads back as the same `Double`, so parsing what was written
/// gives the path that was written.
struct PenPathSVGWritingTests {
    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    /// The path parsed from `data`, written, and parsed again.
    private func reparsed(_ data: String) throws -> (first: PenPath, second: PenPath) {
        let first = try #require(PenPath(svg: data))
        let second = try #require(PenPath(svg: first.svgPathData), "wrote \(first.svgPathData)")
        return (first, second)
    }

    @Test("Each command is written as one absolute SVG command")
    func commands() {
        let path = PenPath(commands: [
            .move(to: pt(0, 0)),
            .line(to: pt(10, 0.5)),
            .quadCurve(to: pt(20, 0), control: pt(15, 5)),
            .cubicCurve(to: pt(30, 0), control1: pt(22, 3), control2: pt(28, 3)),
            .close,
        ])
        #expect(path.svgPathData == "M0 0 L10 0.5 Q15 5 20 0 C22 3 28 3 30 0 Z")
    }

    @Test("Whole numbers are bare, negative zero is zero, fractions are the shortest exact form")
    func numbers() {
        let path = PenPath(commands: [.move(to: pt(-0.0, 1.0 / 3.0)), .line(to: pt(-12, 0.1))])
        #expect(path.svgPathData == "M0 0.3333333333333333 L-12 0.1")
    }

    @Test("Very small and very large numbers read back exactly")
    func exponents() throws {
        let path = PenPath(commands: [.move(to: pt(1e-7, -2.5e-12)), .line(to: pt(1e21, 123_456_789.123_456_78))])
        let parsed = try #require(PenPath(svg: path.svgPathData), "wrote \(path.svgPathData)")
        #expect(parsed == path)
    }

    @Test("Relative commands, H and V parse back equal once written")
    func relative() throws {
        let (first, second) = try reparsed("m10.5 10 l5 5 h3.25 v-2 l-.5.5z m1 1 H40 V-3 c1 2 3 4 5 6 q1 1 2 0")
        #expect(second == first)
    }

    @Test("Smooth curves and arcs parse back equal once written, as their resolved curves")
    func smoothAndArcs() throws {
        let (first, second) = try reparsed("M0 0 C10 0 20 10 20 20 S30 40 40 40 Q50 50 60 40 T80 40 A20 10 30 1 0 120 60 a5 5 0 0 1 10 0")
        #expect(second == first)
        #expect(!first.svgPathData.contains("A"), "arcs are written as the cubics they parsed into")
    }

    @Test("Several subpaths, and drawing on after a close, parse back equal once written")
    func subpaths() throws {
        let (first, second) = try reparsed("M0 0 L10 0 L10 10 Z L5 5 M20 20 L30 30 M40 40")
        #expect(second == first)
    }

    @Test("Path data that does not start with a move parses back equal once written")
    func noLeadingMove() throws {
        let (first, second) = try reparsed("L10 10 L20 0")
        #expect(second == first)
    }

    @Test("A caller can choose how numbers are written")
    func customNumbers() {
        let path = PenPath(commands: [.move(to: pt(1.234, 5)), .line(to: pt(2, 3.06))])
        #expect(path.svgPathData { String(format: "%.1f", $0) } == "M1.2 5.0 L2.0 3.1")
    }

    @Test("A path with no commands writes empty data")
    func empty() {
        #expect(PenPath(commands: []).svgPathData == "")
    }
}
