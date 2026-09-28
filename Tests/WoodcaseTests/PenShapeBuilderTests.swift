import CoreGraphics
import Testing
@testable import Woodcase

struct PenShapeBuilderTests {
    // MARK: - Rectangle

    @Test("Rectangle with no corner radius")
    func plainRectangle() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 50)
        let path = try #require(PenShapeBuilder.buildPath(for: .rectangle, rect: rect))
        let box = path.boundingBox
        #expect(abs(box.width - 100) < 0.01)
        #expect(abs(box.height - 50) < 0.01)
    }

    @Test("Rectangle with uniform corner radius")
    func uniformCornerRadius() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .rectangle,
            rect: rect,
            cornerRadius: PenCornerRadius.Corners(topLeft: 10, topRight: 10, bottomRight: 10, bottomLeft: 10)
        ))
        let box = path.boundingBox
        #expect(abs(box.width - 100) < 0.01)
        #expect(abs(box.height - 100) < 0.01)
    }

    @Test("Rectangle with per-corner radii")
    func perCornerRadii() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .rectangle,
            rect: rect,
            cornerRadius: PenCornerRadius.Corners(topLeft: 0, topRight: 20, bottomRight: 40, bottomLeft: 8)
        ))
        let box = path.boundingBox
        #expect(abs(box.width - 100) < 0.01)
        #expect(abs(box.height - 100) < 0.01)
    }

    @Test("Corner radius clamped to half of smallest dimension (pill shape)")
    func cornerRadiusClampedToPill() throws {
        // Bar graph scenario: height 8, cornerRadius 8 → should produce a pill, not an oval
        let rect = PenRect(x: 0, y: 0, width: 60, height: 8)
        let cr = PenCornerRadius.Corners(topLeft: 8, topRight: 8, bottomRight: 8, bottomLeft: 8)
        let path = try #require(PenShapeBuilder.buildPath(for: .rectangle, rect: rect, cornerRadius: cr))
        let box = path.boundingBox

        // Path should fill the full rect (not be smaller due to degenerate arcs)
        #expect(abs(box.width - 60) < 0.5)
        #expect(abs(box.height - 8) < 0.5)

        // The path should be symmetric top-bottom. Sample at x=4 (within the rounded cap):
        // a proper pill has the widest point at y=4 (center), and the path should extend
        // from y=0 to y=8. An unclamped oval would have less vertical extent at the caps.
        // We verify by checking the path contains points at the vertical extremes near the caps.
        #expect(path.contains(CGPoint(x: 4, y: 4)), "Center of left cap should be inside")
        #expect(path.contains(CGPoint(x: 4, y: 1)), "Top of left cap should be inside")
        #expect(path.contains(CGPoint(x: 4, y: 7)), "Bottom of left cap should be inside")
    }

    @Test("Per-corner radii clamped to half dimensions")
    func perCornerRadiiClamped() throws {
        let rect = PenRect(x: 0, y: 0, width: 20, height: 10)
        // cornerRadius 12 exceeds both width/2 (10) and height/2 (5) → should clamp to 5
        let cr = PenCornerRadius.Corners(topLeft: 12, topRight: 12, bottomRight: 12, bottomLeft: 12)
        let path = try #require(PenShapeBuilder.buildPath(for: .rectangle, rect: rect, cornerRadius: cr))
        let box = path.boundingBox
        #expect(abs(box.width - 20) < 0.5)
        #expect(abs(box.height - 10) < 0.5)
    }

    // MARK: - Ellipse

    @Test("Full ellipse")
    func fullEllipse() throws {
        let rect = PenRect(x: 0, y: 0, width: 120, height: 80)
        let path = try #require(PenShapeBuilder.buildPath(for: .ellipse(), rect: rect))
        let box = path.boundingBox
        #expect(abs(box.width - 120) < 0.5)
        #expect(abs(box.height - 80) < 0.5)
    }

    @Test("Ellipse with arc (270 degree sweep)")
    func arcEllipse() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .ellipse(startAngle: 0, sweepAngle: 270),
            rect: rect
        ))
        // Arc should create a pie slice, not a full circle
        #expect(path.boundingBox.width > 0)
    }

    @Test("Ellipse with inner radius (donut)")
    func donutEllipse() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .ellipse(innerRadius: 0.5),
            rect: rect
        ))
        let box = path.boundingBox
        #expect(abs(box.width - 100) < 0.5)
        #expect(abs(box.height - 100) < 0.5)
    }

    // MARK: - Polygon

    @Test("Hexagon")
    func hexagon() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .polygon(count: 6),
            rect: rect
        ))
        let box = path.boundingBox
        // Hexagon inscribed in 100x100 — vertices touch the bounding rect
        #expect(box.width > 80)
        #expect(box.height > 80)
    }

    @Test("Triangle")
    func triangle() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .polygon(count: 3),
            rect: rect
        ))
        #expect(path.boundingBox.width > 0)
        #expect(path.boundingBox.height > 0)
    }

    // MARK: - Line

    @Test("Diagonal line")
    func diagonalLine() throws {
        let rect = PenRect(x: 0, y: 0, width: 120, height: 80)
        let path = try #require(PenShapeBuilder.buildPath(for: .line, rect: rect))
        let box = path.boundingBox
        #expect(abs(box.minX - 0) < 0.01)
        #expect(abs(box.minY - 0) < 0.01)
        #expect(abs(box.maxX - 120) < 0.01)
        #expect(abs(box.maxY - 80) < 0.01)
    }

    // MARK: - Path

    @Test("SVG path geometry")
    func svgPath() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .path(geometry: "M 0 0 L 100 0 L 100 100 L 0 100 Z"),
            rect: rect
        ))
        let box = path.boundingBox
        #expect(abs(box.width - 100) < 0.01)
        #expect(abs(box.height - 100) < 0.01)
    }

    @Test("Empty path geometry returns nil")
    func emptyPathGeometry() {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        #expect(PenShapeBuilder.buildPath(for: .path(geometry: nil), rect: rect) == nil)
    }

    @Test("Invalid path geometry returns nil")
    func invalidPathGeometry() {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        #expect(PenShapeBuilder.buildPath(for: .path(geometry: "not valid"), rect: rect) == nil)
    }
}
