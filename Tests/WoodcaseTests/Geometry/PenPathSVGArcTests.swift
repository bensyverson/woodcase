import Foundation
import Testing
@testable import Woodcase

/// Pins how an SVG elliptical arc resolves to cubic Béziers (W3C SVG 1.1, F.6), at most
/// 90° per segment, including its degenerate cases and the compact flag syntax.
struct PenPathSVGArcTests {
    private func commands(_ data: String) -> [PenPathCommand]? {
        PenPath(svg: data)?.commands
    }

    private func end(of command: PenPathCommand) -> PenPoint? {
        switch command {
        case let .move(to), let .line(to), let .quadCurve(to, _), let .cubicCurve(to, _, _): to
        case .close: nil
        }
    }

    private func isCubic(_ command: PenPathCommand) -> Bool {
        if case .cubicCurve = command { return true }
        return false
    }

    private func near(_ point: PenPoint?, _ x: Double, _ y: Double) -> Bool {
        guard let point else { return false }
        return abs(point.x - x) < 1e-9 && abs(point.y - y) < 1e-9
    }

    @Test("A semicircle is two cubics, passing over the top when sweep is 1 (y down)")
    func semicircle() throws {
        let parsed = try #require(commands("M 0 0 A 50 50 0 0 1 100 0"))
        try #require(parsed.count == 3)
        #expect(parsed.dropFirst().allSatisfy(isCubic))
        #expect(near(end(of: parsed[1]), 50, -50))
        #expect(near(end(of: parsed[2]), 100, 0))
    }

    @Test("Sweep 0 passes underneath")
    func semicircleOtherSweep() throws {
        let parsed = try #require(commands("M 0 0 A 50 50 0 0 0 100 0"))
        try #require(parsed.count == 3)
        #expect(near(end(of: parsed[1]), 50, 50))
    }

    @Test("a is relative to the current point")
    func relativeArc() throws {
        let parsed = try #require(commands("M 10 10 a 50 50 0 0 1 100 0"))
        try #require(parsed.count == 3)
        #expect(near(parsed.last.flatMap(end), 110, 10))
        #expect(near(end(of: parsed[1]), 60, -40))
    }

    @Test("The large-arc flag picks the long way round: one segment short, four long")
    func largeArcFlag() throws {
        let small = try #require(commands("M 0 0 A 50 50 0 0 0 50 0"))
        let large = try #require(commands("M 0 0 A 50 50 0 1 0 50 0"))
        #expect(small.count == 2)
        #expect(large.count == 5)
        #expect(near(large.last.flatMap(end), 50, 0))
    }

    @Test("Radii too small for the chord are scaled up to reach it")
    func radiiScaledUp() throws {
        let parsed = try #require(commands("M 0 0 A 1 1 0 0 1 100 0"))
        try #require(parsed.count == 3)
        #expect(near(end(of: parsed[1]), 50, -50))
    }

    @Test("Negative radii are read as their magnitude")
    func negativeRadii() throws {
        let parsed = try #require(commands("M 0 0 A -50 -50 0 0 1 100 0"))
        try #require(parsed.count == 3)
        #expect(near(end(of: parsed[1]), 50, -50))
        #expect(parsed == commands("M 0 0 A 50 50 0 0 1 100 0"))
    }

    @Test("A zero radius draws a straight line")
    func zeroRadius() {
        #expect(commands("M 0 0 A 0 10 0 0 1 50 50") == [
            .move(to: PenPoint(x: 0, y: 0)), .line(to: PenPoint(x: 50, y: 50)),
        ])
    }

    @Test("An arc to the current point draws nothing")
    func zeroLengthArc() {
        #expect(commands("M 10 10 A 5 5 0 0 1 10 10") == [.move(to: PenPoint(x: 10, y: 10))])
    }

    @Test("A rotated ellipse's arc ends at its endpoint")
    func rotatedArc() throws {
        let parsed = try #require(commands("M 0 0 A 60 30 45 0 1 80 40"))
        #expect(parsed.dropFirst().allSatisfy(isCubic))
        #expect(near(parsed.last.flatMap(end), 80, 40))
    }

    @Test("Flags may be written without separators", arguments: [
        "M0 0a50 50 0 01100 0",
        "M0 0a50 50 0 0 1100 0",
    ])
    func compactFlags(data: String) throws {
        let parsed = try #require(commands(data))
        #expect(parsed.count == 3)
        #expect(near(parsed.last.flatMap(end), 100, 0))
        #expect(parsed == commands("M0 0a50 50 0 0 1 100 0"))
    }
}
