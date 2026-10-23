import Foundation
import Testing
@testable import Woodcase

/// A path node's box, viewBox and node-local geometry, computed from anchors in the
/// parent's space — and the anchors read back from a node.
struct PenPathFrameTests {
    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    private func corner(_ x: Double, _ y: Double) -> PenPathAnchor {
        PenPathAnchor(point: pt(x, y))
    }

    private func open(_ anchors: PenPathAnchor...) -> [PenPathContour] {
        [PenPathContour(anchors: anchors, isClosed: false)]
    }

    @Test("A straight horizontal path has its box on the line, zero height and no viewBox")
    func horizontal() throws {
        let frame = try #require(PenPathFrame(contours: open(corner(10, 20), corner(110, 20))))
        #expect(frame.x == 10 && frame.y == 20)
        #expect(frame.width == 100 && frame.height == 0)
        #expect(frame.viewBox == nil)
        #expect(frame.geometry == "M0 0 L100 0")
    }

    @Test("A straight vertical path has zero width and no viewBox")
    func vertical() throws {
        let frame = try #require(PenPathFrame(contours: open(corner(5, 40), corner(5, -10))))
        #expect(try frame == PenPathFrame(x: 5, y: -10, width: 0, height: 50, viewBox: nil, path: #require(PenPath(svg: "M0 50 L0 0"))))
    }

    @Test("A curved path's box is its drawn extent, named by a viewBox of the same size")
    func curve() throws {
        let frame = try #require(PenPathFrame(contours: open(
            PenPathAnchor(point: pt(10, 10), outHandle: pt(10, 0)),
            PenPathAnchor(point: pt(30, 10), inHandle: pt(30, 0))
        )))
        #expect(frame.x == 10 && frame.y == 2.5)
        #expect(frame.width == 20 && frame.height == 7.5)
        #expect(frame.viewBox == PenViewBox(x: 0, y: 0, width: 20, height: 7.5))
        #expect(frame.geometry == "M0 7.5 C0 -2.5 20 -2.5 20 7.5")
    }

    @Test("An extent between hundredths widens the box outward to the next hundredth")
    func roundsOutward() throws {
        let frame = try #require(PenPathFrame(contours: open(
            PenPathAnchor(point: pt(0, 0), outHandle: pt(3, -7.77)),
            PenPathAnchor(point: pt(10, 0), inHandle: pt(7, -7.77))
        )))
        // The curve peaks at y = -5.8275.
        #expect(frame.y == -5.83 && frame.height == 5.83)
        #expect(frame.viewBox == PenViewBox(x: 0, y: 0, width: 10, height: 5.83))
    }

    @Test("A coordinate already on a hundredth stays there, though its Double sits just below it")
    func gridValuesAreKept() throws {
        // 3.14 * 100 is 314.00000000000006 and 0.29 * 100 is 28.999999999999996.
        let frame = try #require(PenPathFrame(contours: open(corner(3.14, 0.29), corner(10, 5))))
        #expect(frame.x == 3.14 && frame.y == 0.29)
        #expect(frame.contours() == open(corner(3.14, 0.29), corner(10, 5)))
    }

    @Test("Anchors on hundredths read back from the frame unchanged, open and closed")
    func readsBack() throws {
        let contours = [
            PenPathContour(anchors: [
                PenPathAnchor(point: pt(100.5, 20), mirroringOutHandle: pt(140.25, 0)),
                PenPathAnchor(point: pt(180, 90), inHandle: pt(200, 40), outHandle: pt(150, 120)),
                corner(90, 110),
            ], isClosed: true),
            PenPathContour(anchors: [corner(300, 300), PenPathAnchor(point: pt(320, 280.01), inHandle: pt(310, 250))], isClosed: false),
        ]
        let frame = try #require(PenPathFrame(contours: contours))
        #expect(frame.contours() == contours)
        let reparsed = try #require(PenPath(svg: frame.geometry))
        #expect(reparsed == frame.path)
    }

    @Test("Writing what was read gives the same node properties, however often")
    func stable() throws {
        var contours = [PenPathContour(anchors: [
            PenPathAnchor(point: pt(1.0 / 3.0, 7.123456), outHandle: pt(5.55555, -2.000001)),
            PenPathAnchor(point: pt(1234.567891, 0.1), inHandle: pt(1200.0001, 30.3)),
        ], isClosed: false)]
        let first = try #require(PenPathFrame(contours: contours))
        for _ in 0 ..< 10 {
            contours = try #require(PenPathFrame(contours: contours)).contours()
            #expect(try #require(PenPathFrame(contours: contours)) == first)
        }
    }

    @Test("A horizontal path whose handles overshoot its anchors maps its drawn extent onto the box at scale 1")
    func horizontalOvershoot() throws {
        let contours = open(
            PenPathAnchor(point: pt(0, 5), outHandle: pt(-10, 5)),
            PenPathAnchor(point: pt(20, 5), inHandle: pt(30, 5))
        )
        let frame = try #require(PenPathFrame(contours: contours))
        #expect(frame.viewBox == nil && frame.height == 0)
        let drawn = try #require(frame.path.tightBounds)
        #expect(frame.width == drawn.width)
        #expect(frame.x < 0 && frame.x + frame.width > 20)
        #expect(frame.contours() == contours)
    }

    @Test("A node with no viewBox maps its geometry's drawn extent onto its box, as Pen does")
    func readsWithoutViewBox() throws {
        // Pen draws this at x 20...120, y 20, ignoring the geometry's own offset (pen CLI, 2026-10-23).
        let frame = try #require(PenPathFrame(x: 20, y: 20, width: 100, height: 0, viewBox: nil, geometry: "M37 12 L137 12"))
        #expect(frame.contours() == open(corner(20, 20), corner(120, 20)))
    }

    @Test("A node whose box is larger than its viewBox reads back stretched to the box")
    func readsScaled() throws {
        let frame = try #require(PenPathFrame(
            x: 10, y: 0, width: 200, height: 100,
            viewBox: PenViewBox(x: 0, y: 0, width: 100, height: 50), geometry: "M0 0 L100 50"
        ))
        #expect(frame.contours() == open(corner(10, 0), corner(210, 100)))
    }

    @Test("Geometry in the parent's space gives the same frame as its anchors")
    func fromPath() {
        let contours = open(PenPathAnchor(point: pt(10, 10), outHandle: pt(10, 0)), PenPathAnchor(point: pt(30, 10), inHandle: pt(30, 0)))
        #expect(PenPathFrame(path: PenPath(contours: contours)) == PenPathFrame(contours: contours))
    }

    @Test("A single point is a zero-sized box at the point")
    func singlePoint() throws {
        let frame = try #require(PenPathFrame(contours: open(corner(7, 8))))
        #expect(try frame == PenPathFrame(x: 7, y: 8, width: 0, height: 0, viewBox: nil, path: #require(PenPath(svg: "M0 0"))))
        #expect(frame.contours() == open(corner(7, 8)))
    }

    @Test("No anchors, no frame; unparseable geometry, no frame")
    func empty() {
        #expect(PenPathFrame(contours: []) == nil)
        #expect(PenPathFrame(contours: [PenPathContour(anchors: [], isClosed: false)]) == nil)
        #expect(PenPathFrame(x: 0, y: 0, width: 1, height: 1, viewBox: nil, geometry: "nonsense") == nil)
    }
}
