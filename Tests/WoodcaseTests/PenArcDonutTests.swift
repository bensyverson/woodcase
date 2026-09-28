import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins the outline of an ellipse with both a partial `sweepAngle` and an `innerRadius`.
///
/// Pen draws such an "arc donut" as one closed ring: the outer arc over the sweep, a
/// straight cut along the end angle to the inner ellipse, the inner arc back over the same
/// sweep, and a straight cut along the start angle. Both cuts lie on lines through the
/// centre, at the ellipse's *parametric* angle (the unit-circle angle before the ellipse's
/// non-uniform scale), and the inner ellipse is never drawn outside the sweep.
///
/// `render-arc-donut.pen` has one artboard per case, a white 200×120 ellipse at (20, 20)
/// on black. The references are Pen's 2x PNG exports
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-arc-donut.pen --out <dir> --scale 2`,
/// PNGs copied into `Fixtures/`).
struct PenArcDonutTests {
    private static let fixture = "render-arc-donut"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let scale = 2

    /// Every artboard, in document order.
    private static let artboards = ["quarter", "three-quarter", "negative", "half-thin", "stroked"]

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each arc donut matches Pen's render within MAE 0.38", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Arc donut \(artboard) MAE: \(mae)")
        // max(measured×1.5, measured+0.25) over the worst case (`three-quarter`, 0.127).
        #expect(mae < 0.38, "\(artboard): MAE \(mae)")
    }

    @Test("The inner ellipse outside the sweep is not filled")
    func innerEllipseOutsideSweepIsEmpty() throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: "quarter", in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale)
        ))
        let pixels = try #require(PenFillDomainTests.RGBA(rendered))
        // The quarter sweeps 0°→90° (right to top); the inner ellipse is centred at
        // (120, 80) with radii 50 × 30. (100, 90) is inside it, in the lower-left quadrant.
        #expect(pixels.rgba(atPoint: 100, 90, scale: Self.scale) == .init(r: 0, g: 0, b: 0, a: 255))
        // The ring itself, inside the sweep, is filled.
        #expect(pixels.rgba(atPoint: 180, 60, scale: Self.scale) == .init(r: 255, g: 255, b: 255, a: 255))
    }

    @Test("An arc donut's outline is one closed ring with straight radial cuts")
    func outlineIsOneRing() throws {
        let rect = PenRect(x: 0, y: 0, width: 200, height: 120)
        let path = try #require(PenShapeBuilder.buildPath(
            for: .ellipse(startAngle: 0, sweepAngle: 90, innerRadius: 0.5), rect: rect
        ))
        var subpaths = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { subpaths += 1 }
        }
        #expect(subpaths == 1)
        // The start cut runs along the centre row from the inner (x 150) to the outer (x 200)
        // ellipse; the end cut up the centre column from y 30 to y 0 (y down).
        for rule in [CGPathFillRule.evenOdd, .winding] {
            #expect(path.contains(CGPoint(x: 175, y: 55), using: rule))
            #expect(!path.contains(CGPoint(x: 140, y: 55), using: rule))
            #expect(!path.contains(CGPoint(x: 80, y: 70), using: rule))
            #expect(!path.contains(CGPoint(x: 175, y: 65), using: rule))
        }
    }
}
