import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins where a gradient sits inside its node's box against Pen's own renders.
///
/// `render-gradient-geometry.pen` has one artboard per case: linear gradients at
/// several rotations on square, wide and tall boxes, with an off-centre `center`, a
/// short `size` and interior stops; angular and radial gradients with rotations,
/// centres and non-uniform sizes. The references are Pen's PNG exports at 1x and 2x
/// (`scripts/pen-oracle … --scale 1,2`); the fixture comes from
/// `scripts/gen-paint-geometry-fixtures`.
struct PenGradientGeometrySnapshotTests {
    private static let fixture = "render-gradient-geometry"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard of the fixture, in document order.
    private static let artboards = [
        "lin-sq-r0", "lin-sq-r45", "lin-sq-r90", "lin-sq-r135", "lin-sq-r210",
        "lin-wide-r0", "lin-wide-r45", "lin-wide-r90", "lin-wide-r135", "lin-wide-r210",
        "lin-tall-r0", "lin-tall-r45", "lin-tall-r90", "lin-tall-r135", "lin-tall-r210",
        "lin-wide-r30-centre", "lin-wide-r315-centre-size", "lin-tall-r30-size", "lin-sq-r135-stops",
        "ang-sq-r0", "ang-sq-r45", "ang-sq-r90", "ang-sq-r210",
        "ang-wide-r0", "ang-wide-r45", "ang-wide-r90", "ang-wide-r210",
        "ang-tall-r0", "ang-tall-r45", "ang-tall-r90", "ang-tall-r210",
        "ang-wide-r45-centre", "ang-sq-r45-size", "ang-wide-r0-stops",
        "rad-wide-r45-size", "rad-sq-r30-centre-size",
    ]

    /// max(measured×1.5, measured+0.25) over the worst case (`rad-wide-r45-size` @1x, 0.444).
    private static let threshold = 0.70

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("Each gradient case matches Pen's render within MAE 0.70", arguments: artboards, [1, 2])
    func matchesPen(artboard: String, scale: Int) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)@\(scale)x", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Gradient geometry \(artboard) @\(scale)x MAE: \(mae)")
        #expect(mae < Self.threshold, "\(artboard) @\(scale)x: MAE \(mae)")
    }
}
