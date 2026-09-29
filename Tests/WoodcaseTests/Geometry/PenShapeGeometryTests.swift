import Foundation
import Testing
@testable import Woodcase

/// Pins the CoreGraphics-free outline of each shape: rectangles, ellipses, pie slices,
/// rings and arc donuts, polygons, lines and mapped SVG paths.
struct PenShapeGeometryTests {
    private typealias Element = PenShapeOutline.Element

    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    private func elements(
        _ shape: PenShapeGeometry.Shape,
        _ rect: PenRect,
        cornerRadius: PenCornerRadius.Corners? = nil
    ) -> [Element]? {
        PenShapeGeometry.outline(for: shape, rect: rect, cornerRadius: cornerRadius)?.elements
    }

    private func near(_ a: PenPoint, _ b: PenPoint) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    private static func corners(_ tl: Double, _ tr: Double, _ br: Double, _ bl: Double) -> PenCornerRadius.Corners {
        PenCornerRadius.Corners(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }

    // MARK: - Rectangle

    @Test("A rectangle with no radius is one rect")
    func plainRectangle() {
        let rect = PenRect(x: 1, y: 2, width: 100, height: 50)
        #expect(elements(.rectangle, rect) == [.rect(rect)])
        #expect(elements(.rectangle, rect, cornerRadius: .zero) == [.rect(rect)])
    }

    @Test("A box with a negative size is read as CoreGraphics reads it")
    func negativeSize() {
        #expect(elements(.rectangle, PenRect(x: 100, y: 50, width: -100, height: -50))
            == [.rect(PenRect(x: 0, y: 0, width: 100, height: 50))])
    }

    @Test("A uniform radius is one rounded rect, clamped to half the shorter side")
    func uniformRadius() {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 40)
        #expect(elements(.rectangle, rect, cornerRadius: Self.corners(10, 10, 10, 10)) == [.roundedRect(rect, cornerRadius: 10)])
        #expect(elements(.rectangle, rect, cornerRadius: Self.corners(50, 50, 50, 50)) == [.roundedRect(rect, cornerRadius: 20)])
    }

    @Test("Per-corner radii trace the edges with a tangent arc at each rounded corner")
    func perCornerRadii() {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 50)
        #expect(elements(.rectangle, rect, cornerRadius: Self.corners(10, 0, 5, 0)) == [
            .command(.move(to: pt(10, 0))),
            .command(.line(to: pt(100, 0))),
            .command(.line(to: pt(100, 0))),
            .command(.line(to: pt(100, 45))),
            .tangentArc(tangent1End: pt(100, 50), tangent2End: pt(95, 50), radius: 5),
            .command(.line(to: pt(0, 50))),
            .command(.line(to: pt(0, 50))),
            .command(.line(to: pt(0, 10))),
            .tangentArc(tangent1End: pt(0, 0), tangent2End: pt(10, 0), radius: 10),
            .command(.close),
        ])
    }

    // MARK: - Ellipse

    private static let ellipseBox = PenRect(x: 0, y: 0, width: 200, height: 120)

    @Test("A full ellipse is one ellipse")
    func fullEllipse() {
        #expect(elements(.ellipse(), Self.ellipseBox) == [.ellipse(in: Self.ellipseBox)])
    }

    @Test("A full ring is the outer ellipse and the inner one, inset by the inner radius")
    func fullRing() {
        #expect(elements(.ellipse(innerRadius: 0.5), Self.ellipseBox) == [
            .ellipse(in: Self.ellipseBox),
            .ellipse(in: PenRect(x: 50, y: 30, width: 100, height: 60)),
        ])
    }

    @Test("A pie slice runs from the center round the arc and closes")
    func pieSlice() {
        #expect(elements(.ellipse(startAngle: 0, sweepAngle: 90), Self.ellipseBox) == [
            .command(.move(to: pt(100, 60))),
            .ellipticalArc(
                center: pt(100, 60), radiusX: 100, radiusY: 60,
                startAngle: 0, endAngle: -Double.pi / 2, clockwise: true
            ),
            .command(.close),
        ])
    }

    @Test("An arc donut is the outer arc, then the inner arc back, closed")
    func arcDonut() {
        #expect(elements(.ellipse(startAngle: 0, sweepAngle: 90, innerRadius: 0.5), Self.ellipseBox) == [
            .ellipticalArc(
                center: pt(100, 60), radiusX: 100, radiusY: 60,
                startAngle: 0, endAngle: -Double.pi / 2, clockwise: true
            ),
            .ellipticalArc(
                center: pt(100, 60), radiusX: 50, radiusY: 30,
                startAngle: -Double.pi / 2, endAngle: 0, clockwise: false
            ),
            .command(.close),
        ])
    }

    @Test("A negative sweep turns the other way")
    func negativeSweep() throws {
        let outline = try #require(elements(.ellipse(startAngle: 90, sweepAngle: -180), Self.ellipseBox))
        try #require(outline.count == 3)
        #expect(outline[1] == .ellipticalArc(
            center: pt(100, 60), radiusX: 100, radiusY: 60,
            startAngle: -Double.pi / 2, endAngle: Double.pi / 2, clockwise: false
        ))
    }

    // MARK: - Polygon

    @Test("Fewer than three sides has no outline")
    func degeneratePolygon() {
        #expect(elements(.polygon(count: 2), PenRect(x: 0, y: 0, width: 10, height: 10)) == nil)
    }

    @Test("A sharp polygon starts at the top and runs clockwise through its vertices")
    func sharpPolygon() throws {
        let outline = try #require(elements(.polygon(count: 4), PenRect(x: 0, y: 0, width: 100, height: 100)))
        #expect(outline.count == 5)
        let expected = [pt(50, 0), pt(100, 50), pt(50, 100), pt(0, 50)]
        for (element, vertex) in zip(outline, expected) {
            switch element {
            case let .command(.move(to)), let .command(.line(to)): #expect(near(to, vertex))
            default: Issue.record("unexpected \(element)")
            }
        }
        #expect(outline.last == .command(.close))
    }

    @Test("A rounded polygon starts along its first edge and rounds each vertex toward the next edge's midpoint")
    func roundedPolygon() throws {
        let outline = try #require(elements(.polygon(count: 4, cornerRadius: 10), PenRect(x: 0, y: 0, width: 100, height: 100)))
        try #require(outline.count == 6)
        guard case let .command(.move(start)) = outline[0] else {
            Issue.record("expected a move, got \(outline[0])")
            return
        }
        let edge = 50 * 2.0.squareRoot()
        #expect(near(start, pt(50 + 50 * 10 / edge, 50 * 10 / edge)))
        guard case let .tangentArc(t1, t2, radius) = outline[1] else {
            Issue.record("expected a tangent arc, got \(outline[1])")
            return
        }
        #expect(near(t1, pt(100, 50)))
        #expect(near(t2, pt(75, 75)))
        #expect(radius == 10)
        #expect(outline.last == .command(.close))
    }

    // MARK: - Line and path

    @Test("A line runs corner to corner")
    func line() {
        #expect(elements(.line, PenRect(x: 1, y: 2, width: 10, height: 20)) == [
            .command(.move(to: pt(1, 2))), .command(.line(to: pt(11, 22))),
        ])
    }

    @Test("A path with no geometry, or geometry that does not parse, has no outline", arguments: [nil, "not valid"])
    func unusablePath(geometry: String?) {
        #expect(elements(.path(geometry: geometry), PenRect(x: 0, y: 0, width: 10, height: 10)) == nil)
    }

    @Test("A path's commands are mapped onto the box")
    func mappedPath() {
        #expect(elements(.path(geometry: "M 0 0 L 10 10"), PenRect(x: 5, y: 5, width: 20, height: 20)) == [
            .command(.move(to: pt(5, 5))), .command(.line(to: pt(25, 25))),
        ])
    }
}
