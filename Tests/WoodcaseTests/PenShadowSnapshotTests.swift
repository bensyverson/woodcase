import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins inner and outer shadows against Pen 1.2.14's own exports.
///
/// `render-shadows.pen` (format 2.19, authored here) has one artboard per case: an inner
/// shadow under an inner stroke, one under a frame's children, an `[outer, inner]` pair on a
/// rounded stroked card, an inner shadow in a stroked ellipse, three outer shadows on one
/// node, an outer shadow under a translucent fill, and a fill-less frame whose children
/// overhang it. The references are Pen's PNG exports at 1x and 2x (`scripts/pen-oracle
/// Tests/WoodcaseTests/Fixtures/render-shadows.pen --scale 1,2`, `pen` CLI 0.3.9).
struct PenShadowSnapshotTests {
    private static let fixture = "render-shadows"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard of the fixture, in document order, with its MAE limit.
    ///
    /// Each limit is `max(measured × 1.5, measured + 0.25)` over the worse of the two scales,
    /// rounded up to a hundredth, never looser than the flat 0.75 this replaces; the measured
    /// figure sits beside it (`swift test --filter PenShadowSnapshotTests`, 2026-09-26).
    private static let artboards: [(name: String, limit: Double)] = [
        ("inner-under-stroke", 0.40), // measured 0.145
        ("inner-under-child", 0.65), // measured 0.398
        ("outer-and-inner", 0.52), // measured 0.260
        ("inner-ellipse", 0.47), // measured 0.212
        ("two-outer", 0.71), // measured 0.455
        ("outer-translucent", 0.66), // measured 0.406
        ("outer-frame-children", 0.72), // measured 0.464
    ]

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards.map(\.name))
    }

    @Test("Each shadow case matches Pen's render", arguments: artboards, [1, 2])
    func matchesPen(artboard: (name: String, limit: Double), scale: Int) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard.name, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard.name)@\(scale)x", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Shadows \(artboard.name) @\(scale)x MAE: \(mae)")
        #expect(mae < artboard.limit, "\(artboard.name) @\(scale)x: MAE \(mae)")
    }
}
