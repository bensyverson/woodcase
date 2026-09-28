import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins a text node's inner shadow against Pen's own exports.
///
/// `render-text-shadows.pen` has one artboard per case. Pen casts a text node's inner shadow
/// inside its glyphs: the complement of the glyph outlines casts the shadow, which is kept only
/// where the glyphs cover, over the fill. The glyphs are the silhouette whatever the paint: a
/// quarter-transparent fill, or none at all, still shows the shadow at full strength. The
/// references are Pen's PNG exports at 1x and 2x (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-text-shadows.pen --scale 1,2`).
struct PenTextShadowSnapshotTests {
    private static let fixture = "render-text-shadows"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard of the fixture, in document order, with its MAE limit at 1x and 2x.
    ///
    /// Each limit is the measured MAE + 0.5, rounded up to a hundredth; the measured figure and
    /// the figure before the renderer drew a text's inner shadow sit beside it
    /// (`swift test --filter PenTextShadowSnapshotTests`, 2026-09-27). What is left is the
    /// glyphs' own rasterization — at 800 weight they cover about 4 % more pixels than Pen's,
    /// most at 1x — not the shadow.
    private static let artboards: [(name: String, limits: [Int: Double])] = [
        ("text-inner", [1: 3.68, 2: 1.87]), // measured 3.176, 1.363 (was 5.894, 5.231)
        ("text-inner-soft", [1: 2.21, 2: 1.55]), // measured 1.703, 1.045 (was 3.358, 3.123)
        ("text-inner-outer", [1: 2.88, 2: 1.80]), // measured 2.370, 1.293 (was 4.804, 4.107)
        ("text-inner-wrap", [1: 4.39, 2: 2.52]), // measured 3.886, 2.013 (was 4.861, 3.980)
        ("text-inner-unfilled", [1: 3.91, 2: 2.27]), // measured 3.407, 1.767 (was 9.912, 9.638)
        ("text-inner-translucent", [1: 3.40, 2: 1.88]), // measured 2.896, 1.370 (was 7.561, 7.346)
    ]

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards.map(\.name))
    }

    @Test("Each text inner shadow matches Pen's render", arguments: artboards, [1, 2])
    func matchesPen(artboard: (name: String, limits: [Int: Double]), scale: Int) throws {
        TestFontRegistration.registerTestFonts()
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard.name, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard.name)@\(scale)x", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Text shadows \(artboard.name) @\(scale)x MAE: \(mae)")
        let limit = try #require(artboard.limits[scale])
        #expect(mae < limit, "\(artboard.name) @\(scale)x: MAE \(mae)")
    }
}
