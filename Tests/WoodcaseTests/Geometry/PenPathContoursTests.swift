import Foundation
import Testing
@testable import Woodcase

/// A ``PenPath`` as anchors with handles, and back: the model the pen tool draws and edits.
struct PenPathContoursTests {
    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    private func corner(_ x: Double, _ y: Double) -> PenPathAnchor {
        PenPathAnchor(point: pt(x, y))
    }

    private func contours(_ data: String) throws -> [PenPathContour] {
        try #require(PenPath(svg: data)).contours
    }

    /// The contours written as geometry and read back.
    private func roundTripped(_ contours: [PenPathContour]) throws -> [PenPathContour] {
        let data = PenPath(contours: contours).svgPathData
        return try #require(PenPath(svg: data), "wrote \(data)").contours
    }

    // MARK: Geometry to anchors

    @Test("An open polyline is one open contour of corner anchors")
    func openPolyline() throws {
        #expect(try contours("M0 0 L10 0 L10 10") == [
            PenPathContour(anchors: [corner(0, 0), corner(10, 0), corner(10, 10)], isClosed: false),
        ])
    }

    @Test("A closed polygon is one closed contour, the closing line implied")
    func closedPolygon() throws {
        #expect(try contours("M0 0 L10 0 L10 10 Z") == [
            PenPathContour(anchors: [corner(0, 0), corner(10, 0), corner(10, 10)], isClosed: true),
        ])
    }

    @Test("A drawn segment back to the start before the close is the first anchor, not a new one")
    func explicitClosingLine() throws {
        #expect(try contours("M0 0 L10 0 L10 10 L0 0 Z") == [
            PenPathContour(anchors: [corner(0, 0), corner(10, 0), corner(10, 10)], isClosed: true),
        ])
    }

    @Test("A cubic's control points are the out handle of its start and the in handle of its end")
    func cubicHandles() throws {
        #expect(try contours("M0 0 C5 -5 15 -5 20 0") == [
            PenPathContour(anchors: [
                PenPathAnchor(point: pt(0, 0), outHandle: pt(5, -5)),
                PenPathAnchor(point: pt(20, 0), inHandle: pt(15, -5)),
            ], isClosed: false),
        ])
    }

    @Test("A curved closing segment gives the first anchor its in handle")
    func curvedClose() throws {
        #expect(try contours("M0 0 L10 0 C10 10 0 10 0 0 Z") == [
            PenPathContour(anchors: [
                PenPathAnchor(point: pt(0, 0), inHandle: pt(0, 10)),
                PenPathAnchor(point: pt(10, 0), outHandle: pt(10, 10)),
            ], isClosed: true),
        ])
    }

    @Test("A quadratic becomes the cubic that draws it: handles two thirds of the way to its control")
    func quadraticElevates() throws {
        #expect(try contours("M0 0 Q30 30 60 0") == [
            PenPathContour(anchors: [
                PenPathAnchor(point: pt(0, 0), outHandle: pt(20, 20)),
                PenPathAnchor(point: pt(60, 0), inHandle: pt(40, 20)),
            ], isClosed: false),
        ])
    }

    @Test("An arc becomes the anchors of the cubics it parses into, smooth where they join")
    func arcBecomesCubics() throws {
        let contour = try #require(try contours("M0 0 A50 50 0 1 1 100 0").first)
        #expect(contour.anchors.count > 2)
        #expect(contour.anchors.first?.point == pt(0, 0))
        let end = try #require(contour.anchors.last?.point)
        #expect(abs(end.x - 100) < 1e-9 && abs(end.y) < 1e-9)
        for anchor in contour.anchors.dropFirst().dropLast() {
            #expect([.smooth, .mirrored].contains(anchor.kind), "\(anchor)")
        }
    }

    @Test("Each subpath is its own contour, and relative commands resolve")
    func subpaths() throws {
        #expect(try contours("m0 0 l10 0 l0 10 z m20 0 h5 v5") == [
            PenPathContour(anchors: [corner(0, 0), corner(10, 0), corner(10, 10)], isClosed: true),
            PenPathContour(anchors: [corner(20, 0), corner(25, 0), corner(25, 5)], isClosed: false),
        ])
    }

    @Test("Drawing on after a close without a move starts a contour at the closed one's start")
    func drawAfterClose() throws {
        #expect(try contours("M5 5 L10 5 L10 10 Z L0 0") == [
            PenPathContour(anchors: [corner(5, 5), corner(10, 5), corner(10, 10)], isClosed: true),
            PenPathContour(anchors: [corner(5, 5), corner(0, 0)], isClosed: false),
        ])
    }

    @Test("Path data with no leading move starts at the origin")
    func noLeadingMove() throws {
        #expect(try contours("L10 0") == [PenPathContour(anchors: [corner(0, 0), corner(10, 0)], isClosed: false)])
    }

    // MARK: Anchors to geometry

    @Test("Corner anchors write lines; handles write cubics; a closed contour closes")
    func writesGeometry() {
        let contour = PenPathContour(anchors: [
            corner(0, 0),
            PenPathAnchor(point: pt(10, 0), outHandle: pt(15, 0)),
            PenPathAnchor(point: pt(20, 10), inHandle: pt(20, 5)),
        ], isClosed: true)
        #expect(PenPath(contours: [contour]).svgPathData == "M0 0 L10 0 C15 0 20 5 20 10 Z")
    }

    @Test("An anchor list with broken handles converts to geometry and back unchanged")
    func brokenHandlesRoundTrip() throws {
        let anchors = [
            PenPathAnchor(point: pt(0, 0), outHandle: pt(10, -20)),
            PenPathAnchor(point: pt(40, 0), inHandle: pt(30, -25), outHandle: pt(55, 5)),
            PenPathAnchor(point: pt(80, 40), inHandle: pt(80, 10), outHandle: pt(60, 60)),
            PenPathAnchor(point: pt(10, 50), inHandle: pt(30, 60)),
        ]
        #expect(anchors[1].kind == .broken && anchors[2].kind == .broken)
        let open = [PenPathContour(anchors: anchors, isClosed: false)]
        #expect(try roundTripped(open) == open)
        var closedAnchors = anchors
        closedAnchors[0].inHandle = pt(-5, 30)
        closedAnchors[3].outHandle = pt(0, 52.5)
        let closed = [PenPathContour(anchors: closedAnchors, isClosed: true)]
        #expect(try roundTripped(closed) == closed)
    }

    @Test("Mirrored, smooth and corner anchors, open and closed, in several contours, round trip unchanged")
    func mixedRoundTrip() throws {
        let contours = [
            PenPathContour(anchors: [
                corner(0, 0),
                PenPathAnchor(point: pt(50, 0), mirroringOutHandle: pt(70, 10)),
                PenPathAnchor(point: pt(100, 50), inHandle: pt(100, 30), outHandle: pt(100, 90)),
            ], isClosed: true),
            PenPathContour(anchors: [corner(200, 0), corner(250.25, 0.125)], isClosed: false),
        ]
        #expect(try roundTripped(contours) == contours)
    }

    @Test("An open contour's outer handles draw nothing, so they do not survive")
    func danglingHandlesDrop() throws {
        let contour = PenPathContour(anchors: [
            PenPathAnchor(point: pt(0, 0), inHandle: pt(-10, 0), outHandle: pt(10, 10)),
            PenPathAnchor(point: pt(40, 0), inHandle: pt(30, 10), outHandle: pt(50, -10)),
        ], isClosed: false)
        #expect(try roundTripped([contour]) == [PenPathContour(anchors: [
            PenPathAnchor(point: pt(0, 0), outHandle: pt(10, 10)),
            PenPathAnchor(point: pt(40, 0), inHandle: pt(30, 10)),
        ], isClosed: false)])
    }

    @Test("A closed contour whose last anchor sits on its first keeps both")
    func coincidentEnds() throws {
        let contours = [PenPathContour(anchors: [corner(0, 0), corner(10, 0), corner(10, 10), corner(0, 0)], isClosed: true)]
        #expect(try roundTripped(contours) == contours)
    }

    @Test("A one-anchor contour round trips: a point, a closed point and a closed loop")
    func singleAnchor() throws {
        let contours = [
            PenPathContour(anchors: [corner(5, 5)], isClosed: false),
            PenPathContour(anchors: [corner(8, 8)], isClosed: true),
            PenPathContour(anchors: [PenPathAnchor(point: pt(20, 20), inHandle: pt(30, 40), outHandle: pt(10, 40))], isClosed: true),
        ]
        #expect(try roundTripped(contours) == contours)
    }

    @Test("A contour with no anchors writes nothing")
    func emptyContour() {
        let path = PenPath(contours: [PenPathContour(anchors: [], isClosed: true), PenPathContour(anchors: [corner(1, 2)], isClosed: false)])
        #expect(path.svgPathData == "M1 2")
    }

    @Test("Repeated round trips through geometry text do not drift")
    func noDrift() throws {
        var contours = [PenPathContour(anchors: [
            PenPathAnchor(point: pt(0.1, 0.2), mirroringOutHandle: pt(1.0 / 3.0, 0.7)),
            PenPathAnchor(point: pt(10.3, 7.7), inHandle: pt(9.9, 1e-3), outHandle: pt(12.123456789, 8)),
            PenPathAnchor(point: pt(-4.2, 3.3), inHandle: pt(-4, 5.55)),
        ], isClosed: true)]
        let first = contours
        for _ in 0 ..< 5 {
            contours = try roundTripped(contours)
        }
        #expect(contours == first)
    }
}
