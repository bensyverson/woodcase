import Foundation
import Testing
@testable import Woodcase

/// How an anchor's handles relate — corner, smooth, mirrored or broken — read from its
/// points within ``PenPathAnchor/KindTolerance/standard``.
struct PenPathAnchorKindTests {
    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    private func anchor(in inHandle: PenPoint, out outHandle: PenPoint) -> PenPathAnchor {
        PenPathAnchor(point: pt(0, 0), inHandle: inHandle, outHandle: outHandle)
    }

    @Test("An anchor with neither handle extended is a corner")
    func corner() {
        #expect(PenPathAnchor(point: pt(3, 4)).kind == .corner)
        #expect(!PenPathAnchor(point: pt(3, 4)).hasInHandle)
        #expect(!PenPathAnchor(point: pt(3, 4)).hasOutHandle)
    }

    @Test("Opposite handles of equal length are mirrored")
    func mirrored() {
        #expect(anchor(in: pt(-10, -5), out: pt(10, 5)).kind == .mirrored)
    }

    @Test("Opposite handles of different lengths are smooth")
    func smooth() {
        #expect(anchor(in: pt(-10, -5), out: pt(20, 10)).kind == .smooth)
    }

    @Test("Handles that are not opposite are broken")
    func broken() {
        #expect(anchor(in: pt(-10, 0), out: pt(0, 10)).kind == .broken)
        #expect(anchor(in: pt(10, 0), out: pt(10, 0)).kind == .broken, "both handles on one side")
    }

    @Test("One extended handle has no partner to keep in line, so the anchor is broken")
    func oneHandle() {
        #expect(PenPathAnchor(point: pt(0, 0), outHandle: pt(5, 5)).kind == .broken)
        #expect(PenPathAnchor(point: pt(0, 0), inHandle: pt(5, 5)).kind == .broken)
    }

    @Test("Handles within the angle tolerance of opposite are smooth; just past it, broken")
    func angleTolerance() {
        let tolerance = PenPathAnchor.KindTolerance.standard.angle
        let inside = tolerance * 0.9, outside = tolerance * 1.1
        #expect(anchor(in: pt(-10, 0), out: pt(20 * cos(inside), 20 * sin(inside))).kind == .smooth)
        #expect(anchor(in: pt(-10, 0), out: pt(20 * cos(outside), 20 * sin(outside))).kind == .broken)
    }

    @Test("Lengths within the length tolerance are mirrored; just past it, smooth")
    func lengthTolerance() {
        let tolerance = PenPathAnchor.KindTolerance.standard.lengthRatio
        #expect(anchor(in: pt(-100, 0), out: pt(100 * (1 + tolerance * 0.9), 0)).kind == .mirrored)
        #expect(anchor(in: pt(-100, 0), out: pt(100 * (1 + tolerance * 1.1), 0)).kind == .smooth)
    }

    @Test("A handle shorter than the retraction tolerance counts as retracted")
    func tinyHandle() {
        let tiny = PenPathAnchor.KindTolerance.standard.retractedLength / 2
        #expect(anchor(in: pt(tiny, 0), out: pt(0, -tiny)).kind == .corner)
        #expect(anchor(in: pt(tiny, 0), out: pt(0, 0)).hasInHandle, "geometry still sees it")
    }

    @Test("A caller can pass its own tolerance")
    func customTolerance() {
        let loose = PenPathAnchor.KindTolerance(angle: 0.5, lengthRatio: 0.5, retractedLength: 1)
        #expect(anchor(in: pt(-10, 0), out: pt(12, 3)).kind(tolerance: loose) == .mirrored)
        #expect(anchor(in: pt(-10, 0), out: pt(12, 3)).kind == .broken)
    }

    @Test("A drag pulls mirrored handles: the in handle is the out handle reflected through the point")
    func mirroringInit() {
        let anchor = PenPathAnchor(point: pt(10, 10), mirroringOutHandle: pt(14, 7))
        #expect(anchor.inHandle == pt(6, 13))
        #expect(anchor.outHandle == pt(14, 7))
        #expect(anchor.kind == .mirrored)
    }

    @Test("A circle drawn as arcs reads back as mirrored anchors")
    func parsedCircle() throws {
        let contours = try #require(PenPath(svg: "M100 50 A50 50 0 1 1 0 50 A50 50 0 1 1 100 50 Z")).contours
        let anchors = try #require(contours.first).anchors
        #expect(anchors.count >= 4)
        #expect(anchors.allSatisfy { $0.kind == .mirrored }, "\(anchors.map(\.kind))")
    }

    @Test("Moving an anchor carries its handles with it")
    func translation() {
        let anchor = PenPathAnchor(point: pt(1, 2), inHandle: pt(0, 0), outHandle: pt(3, 3))
        let moved = anchor.mappingPoints { PenPoint(x: $0.x + 10, y: $0.y - 1) }
        #expect(moved == PenPathAnchor(point: pt(11, 1), inHandle: pt(10, -1), outHandle: pt(13, 2)))
    }
}
