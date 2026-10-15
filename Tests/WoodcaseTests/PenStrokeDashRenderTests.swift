import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// How the CG renderer dashes a stroke.
///
/// Dashes flow continuously around the whole outline from a pinned start, clockwise on
/// screen, as SVG starts each shape: a rectangle or rounded rectangle at `(x + r, y)`, an
/// ellipse at its rightmost point, a polygon at its first vertex's rounding, a path or
/// line in its own order (integrator's ruling, 2026-10-14). Every probe here strokes 4 pt
/// red, centered, with butt caps, and samples a pixel well inside a dash or a gap.
struct PenStrokeDashRenderTests {
    private typealias Rendering = PenStrokeDashRendering

    /// A node of `type` at 20, 20 stroked 4 pt with `paint`, dashed by `woodcase`.
    private func node(
        _ type: String, width: Int = 100, height: Int = 60, extra: String = "", paint: String = ##""#FF0000""##,
        woodcase: String
    ) -> String {
        """
        {"type": "\(type)", "id": "n", "x": 20, "y": 20, "width": \(width), "height": \(height), "stroke": \(paint),
         "strokeWidth": 4\(extra), "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
        """
    }

    private func inked(_ grid: PixelGrid, _ x: Int, _ y: Int) -> Bool {
        grid.pixel(x, y).a > 200
    }

    private func clear(_ grid: PixelGrid, _ x: Int, _ y: Int) -> Bool {
        grid.pixel(x, y).a < 30
    }

    // MARK: - Rectangles

    @Test("A rectangle's dashes start at its top-left corner and run right along the top")
    func rectangleStartsTopLeft() throws {
        let grid = try Rendering.grid(node("rectangle", woodcase: #""strokeDash": [10, 10]"#))
        #expect(inked(grid, 25, 20), "first dash: \(grid.pixel(25, 20))")
        #expect(clear(grid, 35, 20), "first gap: \(grid.pixel(35, 20))")
        #expect(inked(grid, 45, 20), "second dash: \(grid.pixel(45, 20))")
    }

    @Test("A rounded rectangle's dashes start where the top edge leaves the top-left corner")
    func roundedRectangleStartsPastTheRadius() throws {
        let grid = try Rendering.grid(node("rectangle", extra: #", "cornerRadius": 10"#, woodcase: #""strokeDash": [10, 10]"#))
        #expect(inked(grid, 35, 20), "first dash: \(grid.pixel(35, 20))")
        #expect(clear(grid, 45, 20), "first gap: \(grid.pixel(45, 20))")
        #expect(inked(grid, 55, 20), "second dash: \(grid.pixel(55, 20))")
    }

    @Test("A rounded rectangle's dashes flow on around the corner, measured along the arc")
    func dashesFlowAroundCorners() throws {
        // The top edge runs 80 from (30, 20), the corner a quarter turn of radius 10
        // (15.71), so the right edge at y = 30 + d lies 95.71 + d along the outline.
        let grid = try Rendering.grid(node("rectangle", extra: #", "cornerRadius": 10"#, woodcase: #""strokeDash": [10, 10]"#))
        #expect(inked(grid, 120, 39), "105 along, in a dash: \(grid.pixel(120, 39))")
        #expect(clear(grid, 120, 49), "115 along, in a gap: \(grid.pixel(120, 49))")
    }

    @Test("The offset moves the pattern back along the outline")
    func offsetShiftsThePattern() throws {
        let grid = try Rendering.grid(node("rectangle", woodcase: #""strokeDash": [10, 10], "strokeDashOffset": 10"#))
        #expect(clear(grid, 25, 20), "the first 10 is now a gap: \(grid.pixel(25, 20))")
        #expect(inked(grid, 35, 20), "then a dash: \(grid.pixel(35, 20))")
    }

    @Test("A painted stroke is dashed too")
    func paintedStrokeIsDashed() throws {
        let gradient = ##"{"type": "gradient", "gradientType": "linear", "colors": [{"color": "#FF0000", "position": 0}, {"color": "#0000FF", "position": 1}]}"##
        let grid = try Rendering.grid(node("rectangle", paint: gradient, woodcase: #""strokeDash": [10, 10]"#))
        #expect(inked(grid, 25, 20), "first dash: \(grid.pixel(25, 20))")
        #expect(clear(grid, 35, 20), "first gap: \(grid.pixel(35, 20))")
    }

    // MARK: - Ellipses, paths, polygons

    @Test("An ellipse's dashes start at its rightmost point and run clockwise, down the right side")
    func ellipseStartsRightRunsClockwise() throws {
        // A 6-long dash then a 34-long gap: just below the start is inked; just above it is
        // the end of the outline, which falls in a gap — reversed, the two would swap.
        let grid = try Rendering.grid(node("ellipse", woodcase: #""strokeDash": [6, 34]"#))
        #expect(inked(grid, 119, 52), "just below the start: \(grid.pixel(119, 52))")
        #expect(clear(grid, 119, 47), "just above the start: \(grid.pixel(119, 47))")
    }

    @Test("A path's dashes start at its first point and flow on around its corners")
    func pathInItsOwnOrder() throws {
        let grid = try Rendering.grid(node(
            "path", extra: #", "geometry": "M0 0 L100 0 L100 60""#, woodcase: #""strokeDash": [10, 10]"#
        ))
        #expect(inked(grid, 25, 20), "first dash: \(grid.pixel(25, 20))")
        #expect(clear(grid, 35, 20), "first gap: \(grid.pixel(35, 20))")
        #expect(inked(grid, 120, 25), "105 along, past the corner: \(grid.pixel(120, 25))")
        #expect(clear(grid, 120, 35), "115 along: \(grid.pixel(120, 35))")
    }

    // MARK: - Outlines, pinned

    @Test("A rounded rectangle's outline starts at (x + r, y) and runs right")
    func roundedRectangleOutlineStart() throws {
        let node = PenNode(id: "r", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(
            cornerRadius: .uniform(.literal(10))
        )))
        let path = try #require(PenShapeBuilder.buildPath(for: node, rect: PenRect(x: 0, y: 0, width: 100, height: 60)))
        let points = Self.points(of: path)
        #expect(points.first == CGPoint(x: 10, y: 0))
        #expect(points.dropFirst().first == CGPoint(x: 90, y: 0), "then right along the top: \(points)")
    }

    @Test("A rounded polygon's outline starts where its first vertex's rounding ends, not short of it")
    func roundedPolygonOutlineStart() throws {
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100)
        let radius = 10.0
        let outline = try #require(PenShapeGeometry.polygon(in: rect, sides: 3, cornerRadius: radius))
        guard case let .command(.move(to: start))? = outline.elements.first else {
            Issue.record("the outline does not open with a move: \(outline.elements)")
            return
        }
        let vertices = try #require(PenShapeGeometry.polygonVertices(in: rect, sides: 3))
        let (v0, v1, last) = (vertices[0], vertices[1], vertices[2])
        let toNext = (x: v1.x - v0.x, y: v1.y - v0.y)
        let toLast = (x: last.x - v0.x, y: last.y - v0.y)
        let lengthNext = (toNext.x * toNext.x + toNext.y * toNext.y).squareRoot()
        let lengthLast = (toLast.x * toLast.x + toLast.y * toLast.y).squareRoot()
        let angle = acos((toNext.x * toLast.x + toNext.y * toLast.y) / (lengthNext * lengthLast))
        let along = radius / tan(angle / 2)
        #expect(abs(start.x - (v0.x + toNext.x / lengthNext * along)) < 1e-9, "\(start)")
        #expect(abs(start.y - (v0.y + toNext.y / lengthNext * along)) < 1e-9, "\(start)")
    }

    /// Every point a path's elements end on, in order.
    private static func points(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint, .addLineToPoint: points.append(element.points[0])
            case .addQuadCurveToPoint: points.append(element.points[1])
            case .addCurveToPoint: points.append(element.points[2])
            case .closeSubpath: break
            @unknown default: break
            }
        }
        return points
    }
}
