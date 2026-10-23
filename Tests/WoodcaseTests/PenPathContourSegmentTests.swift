//
//  PenPathContourSegmentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Finding the point of a contour nearest a pointer, and splitting a segment there without
/// changing the drawn shape — the pen tool's "add an anchor on a segment" (leaf pHYXmJ).
struct PenPathContourSegmentTests {
    private static func point(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    /// An open contour: a straight segment, then a cubic.
    private static let open = PenPathContour(anchors: [
        PenPathAnchor(point: point(0, 0)),
        PenPathAnchor(point: point(100, 0), outHandle: point(150, 0)),
        PenPathAnchor(point: point(200, 100), inHandle: point(200, 50)),
    ], isClosed: false)

    /// A closed triangle whose closing segment is a cubic.
    private static let closed = PenPathContour(anchors: [
        PenPathAnchor(point: point(0, 0), inHandle: point(-40, 20)),
        PenPathAnchor(point: point(100, 0)),
        PenPathAnchor(point: point(50, 80), outHandle: point(10, 90)),
    ], isClosed: true)

    /// A segment's point at `t`: linear on a straight segment, the Bernstein form on a cubic.
    private static func evaluate(_ contour: PenPathContour, segment: Int, at t: Double) -> PenPoint {
        let from = contour.anchors[segment]
        let to = contour.anchors[(segment + 1) % contour.anchors.count]
        let (p0, p1, p2, p3) = (from.point, from.outHandle, to.inHandle, to.point)
        if !from.hasOutHandle, !to.hasInHandle {
            return point(p0.x + (p3.x - p0.x) * t, p0.y + (p3.y - p0.y) * t)
        }
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return point(
            a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    private static func distance(_ a: PenPoint, _ b: PenPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// The nearest distance by brute force over a fine sampling of every segment.
    private static func bruteNearest(_ contour: PenPathContour, to target: PenPoint) -> Double {
        let count = contour.isClosed ? contour.anchors.count : contour.anchors.count - 1
        var best = Double.infinity
        for segment in 0 ..< count {
            for step in 0 ... 20000 {
                best = min(best, distance(evaluate(contour, segment: segment, at: Double(step) / 20000), target))
            }
        }
        return best
    }

    /// The hit is at least as near as a fine brute-force search finds — the search's own
    /// spacing makes it the less accurate of the two — and no nearer point lies a hair
    /// either side of it, to 10⁻⁶.
    private static func expectNearest(
        _ hit: PenPathContour.NearestPoint, in contour: PenPathContour, to target: PenPoint,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let brute = bruteNearest(contour, to: target)
        #expect(hit.distance <= brute + 1e-9, sourceLocation: sourceLocation)
        #expect(brute - hit.distance < 1e-4, sourceLocation: sourceLocation)
        for nudge in [-1e-4, -1e-6, 1e-6, 1e-4] {
            let t = min(max(hit.t + nudge, 0), 1)
            let nearby = distance(evaluate(contour, segment: hit.segment, at: t), target)
            #expect(nearby >= hit.distance - 1e-6, "at t + \(nudge)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Nearest point

    @Test("The nearest point on a straight segment is the exact projection")
    func nearestOnLine() throws {
        let hit = try #require(Self.open.nearestPoint(to: Self.point(30, 12)))
        #expect(hit.segment == 0)
        #expect(abs(hit.t - 0.3) < 1e-12)
        #expect(Self.distance(hit.point, Self.point(30, 0)) < 1e-12)
        #expect(abs(hit.distance - 12) < 1e-12)
    }

    @Test("A point past a straight segment's end is nearest that end")
    func nearestClampsToEnd() throws {
        let hit = try #require(Self.open.nearestPoint(to: Self.point(-30, -40)))
        #expect(hit.segment == 0)
        #expect(hit.t == 0)
        #expect(abs(hit.distance - 50) < 1e-12)
    }

    @Test("The nearest point on a cubic matches a fine brute-force search", arguments: [
        (160.0, 20.0), (190.0, 60.0), (120.0, 40.0), (250.0, 120.0), (175.0, 35.0),
    ])
    func nearestOnCubic(x: Double, y: Double) throws {
        let target = Self.point(x, y)
        let hit = try #require(Self.open.nearestPoint(to: target))
        #expect(hit.segment == 1)
        Self.expectNearest(hit, in: Self.open, to: target)
        #expect(Self.distance(hit.point, Self.evaluate(Self.open, segment: 1, at: hit.t)) < 1e-9)
        #expect(abs(Self.distance(hit.point, target) - hit.distance) < 1e-9)
    }

    @Test("A closed contour's last segment is the closing one back to the first anchor")
    func nearestOnClosingSegment() throws {
        let target = Self.point(10, 50)
        let hit = try #require(Self.closed.nearestPoint(to: target))
        #expect(hit.segment == 2)
        Self.expectNearest(hit, in: Self.closed, to: target)
    }

    @Test("A contour with no segment has no nearest point")
    func nearestOnNothing() {
        #expect(PenPathContour(anchors: [], isClosed: false).nearestPoint(to: .zero) == nil)
        #expect(PenPathContour(anchors: [PenPathAnchor(point: .zero)], isClosed: false).nearestPoint(to: .zero) == nil)
    }

    // MARK: - Splitting

    /// Every point of the old segment lies on one of the two new ones, at the matching
    /// parameter, so the drawn shape is unchanged.
    private static func expectSameShape(
        _ old: PenPathContour, segment: Int, at t: Double, _ new: PenPathContour, index: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for step in 0 ... 100 {
            let s = Double(step) / 100
            let original = evaluate(old, segment: segment, at: s)
            let split = s <= t
                ? evaluate(new, segment: index - 1, at: t == 0 ? 0 : s / t)
                : evaluate(new, segment: index, at: (s - t) / (1 - t))
            #expect(distance(original, split) < 1e-9, "at \(s)", sourceLocation: sourceLocation)
        }
    }

    @Test("Splitting a cubic leaves its shape and makes a smooth anchor between shortened handles")
    func splitCubic() {
        let (contour, index) = Self.open.insertingAnchor(inSegment: 1, at: 0.4)

        #expect(index == 2)
        #expect(contour.anchors.count == 4)
        #expect(!contour.isClosed)
        let added = contour.anchors[2]
        #expect(added.kind != .corner)
        let cross = (added.inHandle.x - added.point.x) * (added.outHandle.y - added.point.y)
            - (added.inHandle.y - added.point.y) * (added.outHandle.x - added.point.x)
        #expect(abs(cross) < 1e-9)
        #expect(Self.distance(contour.anchors[1].outHandle, Self.point(120, 0)) < 1e-12)
        #expect(Self.distance(contour.anchors[3].inHandle, Self.point(200, 70)) < 1e-12)
        #expect(contour.anchors[1].point == Self.open.anchors[1].point)
        #expect(contour.anchors[1].inHandle == Self.open.anchors[1].inHandle)
        Self.expectSameShape(Self.open, segment: 1, at: 0.4, contour, index: index)
    }

    @Test("Splitting a straight segment adds a corner anchor at the lerp")
    func splitLine() {
        let (contour, index) = Self.open.insertingAnchor(inSegment: 0, at: 0.25)

        #expect(index == 1)
        #expect(contour.anchors[1] == PenPathAnchor(point: Self.point(25, 0)))
        #expect(contour.anchors[0] == Self.open.anchors[0])
        #expect(contour.anchors[2] == Self.open.anchors[1])
        Self.expectSameShape(Self.open, segment: 0, at: 0.25, contour, index: index)
    }

    @Test("Splitting the closing segment appends the anchor and keeps the contour closed")
    func splitClosingSegment() {
        let (contour, index) = Self.closed.insertingAnchor(inSegment: 2, at: 0.5)

        #expect(index == 3)
        #expect(contour.isClosed)
        #expect(contour.anchors.count == 4)
        Self.expectSameShape(Self.closed, segment: 2, at: 0.5, contour, index: index)
    }

    @Test("Splitting where the nearest point lands draws the same path")
    func splitAtNearestPoint() throws {
        let hit = try #require(Self.closed.nearestPoint(to: Self.point(70, 50)))
        let (contour, index) = Self.closed.insertingAnchor(inSegment: hit.segment, at: hit.t)

        #expect(Self.distance(contour.anchors[index].point, hit.point) < 1e-9)
        Self.expectSameShape(Self.closed, segment: hit.segment, at: hit.t, contour, index: index)
    }
}
