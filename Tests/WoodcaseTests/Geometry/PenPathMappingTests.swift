import Foundation
import Testing
@testable import Woodcase

/// Pins a path's tight bounds and how it is mapped onto a node box: through its viewBox
/// when it has a usable one, otherwise by stretching its tight bounds to fill the box.
struct PenPathMappingTests {
    private func path(_ data: String) throws -> PenPath {
        try #require(PenPath(svg: data))
    }

    private func pt(_ x: Double, _ y: Double) -> PenPoint {
        PenPoint(x: x, y: y)
    }

    // MARK: - Tight bounds

    @Test("A line's bounds are its endpoints")
    func lineBounds() throws {
        #expect(try path("M 10 20 L 100 200").tightBounds == PenRect(x: 10, y: 20, width: 90, height: 180))
    }

    @Test("A cubic's bounds reach its extremum, not its control points")
    func cubicBounds() throws {
        #expect(try path("M 0 0 C 0 100 100 100 100 0").tightBounds == PenRect(x: 0, y: 0, width: 100, height: 75))
    }

    @Test("A quadratic's bounds reach its extremum, not its control point")
    func quadraticBounds() throws {
        #expect(try path("M 0 0 Q 50 100 100 0").tightBounds == PenRect(x: 0, y: 0, width: 100, height: 50))
    }

    @Test("A path with no points has no bounds")
    func emptyBounds() {
        #expect(PenPath(commands: []).tightBounds == nil)
        #expect(PenPath(commands: [.close]).tightBounds == nil)
    }

    // MARK: - Source region

    @Test("The source region is a usable viewBox, else the tight bounds")
    func sourceRegion() throws {
        let line = try path("M 10 20 L 30 60")
        #expect(line.sourceRegion(viewBox: PenViewBox(x: -5, y: -5, width: 20, height: 20))
            == PenRect(x: -5, y: -5, width: 20, height: 20))
        #expect(line.sourceRegion(viewBox: nil) == PenRect(x: 10, y: 20, width: 20, height: 40))
        #expect(line.sourceRegion(viewBox: PenViewBox(x: 0, y: 0, width: 0, height: 10))
            == PenRect(x: 10, y: 20, width: 20, height: 40))
        #expect(PenPath(commands: [.close]).sourceRegion(viewBox: nil) == nil)
    }

    // MARK: - Mapping

    @Test("A viewBox is mapped onto the box, non-uniformly")
    func viewBoxMapping() throws {
        let rect = PenRect(x: 100, y: 200, width: 50, height: 100)
        let mapped = try path("M 0 0 L 10 10").mapped(onto: rect, viewBox: PenViewBox(x: 0, y: 0, width: 10, height: 10))
        #expect(mapped.commands == [.move(to: pt(100, 200)), .line(to: pt(150, 300))])
    }

    @Test("A viewBox's origin is moved to the box's origin")
    func viewBoxOffset() throws {
        let rect = PenRect(x: 100, y: 200, width: 50, height: 100)
        let mapped = try path("M 0 0").mapped(onto: rect, viewBox: PenViewBox(x: -5, y: -5, width: 20, height: 20))
        #expect(mapped.commands == [.move(to: pt(112.5, 225))])
    }

    @Test("Without a viewBox the tight bounds are stretched to fill the box")
    func boundsStretch() throws {
        let mapped = try path("M 10 10 L 20 30").mapped(onto: PenRect(x: 0, y: 0, width: 100, height: 100), viewBox: nil)
        #expect(mapped.commands == [.move(to: pt(0, 0)), .line(to: pt(100, 100))])
    }

    @Test("An axis with no extent is translated, not scaled")
    func flatAxis() throws {
        let mapped = try path("M 10 50 L 30 50").mapped(onto: PenRect(x: 0, y: 5, width: 100, height: 40), viewBox: nil)
        #expect(mapped.commands == [.move(to: pt(0, 5)), .line(to: pt(100, 5))])
    }

    @Test("A single point is moved to the box's origin")
    func singlePoint() throws {
        let mapped = try path("M 5 5").mapped(onto: PenRect(x: 10, y: 10, width: 50, height: 50), viewBox: nil)
        #expect(mapped.commands == [.move(to: pt(10, 10))])
    }

    @Test("Every control point is mapped with its curve")
    func curvesMapped() throws {
        let mapped = try path("M 0 0 Q 5 10 10 0 C 0 0 0 0 0 0")
            .mapped(onto: PenRect(x: 0, y: 0, width: 20, height: 20), viewBox: PenViewBox(x: 0, y: 0, width: 10, height: 10))
        #expect(mapped.commands == [
            .move(to: pt(0, 0)),
            .quadCurve(to: pt(20, 0), control: pt(10, 20)),
            .cubicCurve(to: pt(0, 0), control1: pt(0, 0), control2: pt(0, 0)),
        ])
    }

    @Test("A path with no points is returned unchanged")
    func unmappable() {
        let closeOnly = PenPath(commands: [.close])
        #expect(closeOnly.mapped(onto: PenRect(x: 1, y: 1, width: 1, height: 1), viewBox: nil) == closeOnly)
    }
}
