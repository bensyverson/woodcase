import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins a group's outer and inner shadows against Pen 1.2.14's own exports.
///
/// `render-group-shadows.pen` has one artboard per case. Pen casts a group's shadow from the
/// combined opaque outline of its descendants, reached through groups only: a translucent
/// child casts at full strength, a frame child casts its box and its own children nothing, a
/// line casts nothing, and a child's own shadow feeds nothing. A group's inner shadow falls
/// inside that same outline, over the children. The references are Pen's PNG exports at 1x and
/// 2x (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-group-shadows.pen --scale 1,2`).
struct PenGroupShadowSnapshotTests {
    private static let fixture = "render-group-shadows"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard of the fixture, in document order, with its MAE limit.
    ///
    /// Each limit is `max(measured × 1.5, measured + 0.25)` over the worse of the two scales,
    /// rounded up to a hundredth; the measured figure sits beside it
    /// (`swift test --filter PenGroupShadowSnapshotTests`, 2026-09-26); "was" is the figure before
    /// the renderer cast a group's shadows from its silhouette.
    private static let artboards: [(name: String, limit: Double)] = [
        ("group-outer", 0.47), // measured 0.212 (was 0.212)
        ("group-translucent", 0.69), // measured 0.437 (was 6.405)
        ("group-stroke-path", 0.43), // measured 0.173 (was 3.480)
        ("group-inner", 0.53), // measured 0.275 (was 6.739: no group inner shadow)
        ("group-child-shadow", 0.53), // measured 0.276 (was 0.943)
        ("group-nested", 0.56), // measured 0.300 (was 0.300)
        ("group-frame-child", 0.36), // measured 0.106 (was 6.507)
    ]

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards.map(\.name))
    }

    @Test("Each group shadow case matches Pen's render", arguments: artboards, [1, 2])
    func matchesPen(artboard: (name: String, limit: Double), scale: Int) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard.name, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard.name)@\(scale)x", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Group shadows \(artboard.name) @\(scale)x MAE: \(mae)")
        #expect(mae < artboard.limit, "\(artboard.name) @\(scale)x: MAE \(mae)")
    }
}
