import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins the Core Graphics renderer's outer shadows of stroked nodes against Pen's exports.
///
/// `render-stroke-shadows.pen` (format 2.19, `scripts/gen-stroke-shadows-fixture`) has one
/// board per case: a grey node stroked green 12 pt wide casting a white outer shadow —
/// outside, centred and inside, rounded, translucent, per side, on a frame with a child, an
/// ellipse, a polygon, a path and two lines — and an inside stroke over an inner shadow.
/// Pen casts the shadow from the silhouette the stroke band grows, knocks it out under the
/// band, and casts nothing from a line. The references are Pen's 2x exports
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-stroke-shadows.pen --scale 2`,
/// `pen` CLI, 2026-09-28).
struct PenStrokeShadowSnapshotTests {
    private static let fixture = "render-stroke-shadows"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every board of the fixture, in document order, with its MAE limit at 2x.
    ///
    /// Each limit is `max(measured × 1.5, measured + 0.25)`, rounded up to a hundredth, the
    /// measured figure beside it (`swift test --filter PenStrokeShadowSnapshotTests`,
    /// 2026-09-28). The two lines were far from Pen until leaf B7M4na (2026-09-28):
    /// `PenShadowSilhouette` cast a line's shadow from its stroke, where Pen casts none; it
    /// now casts nothing from a line, matching the group silhouette rule.
    private static let artboards: [(name: String, limit: Double)] = [
        ("rect-outer", 0.36), // measured 0.109
        ("rect-center", 0.35), // measured 0.099
        ("rect-inner", 0.34), // measured 0.089
        ("rect-round-outer", 0.39), // measured 0.134
        ("rect-translucent-outer", 0.36), // measured 0.109
        ("frame-perside-outer", 0.36), // measured 0.100
        ("frame-perside-center", 0.35), // measured 0.094
        ("frame-child-outer", 0.36), // measured 0.109
        ("ellipse-outer", 0.43), // measured 0.179
        ("polygon-outer", 0.39), // measured 0.140
        ("path-outer", 0.35), // measured 0.099
        ("line-diagonal", 0.26), // measured 0.006, was 3.78 (measured 2.520) before B7M4na fixed the line shadow
        ("line-flat", 0.25), // measured 0.000, was 6.86 (measured 4.569) before B7M4na fixed the line shadow
        ("inner-under-inner-stroke", 0.25), // measured 0.000
    ]

    @Test("The case list names every board of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards.map(\.name))
    }

    @Test("Each stroked shadow matches Pen's render", arguments: artboards)
    func matchesPen(artboard: (name: String, limit: Double)) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard.name, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: 2
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard.name)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Stroke shadows \(artboard.name) @2x MAE: \(mae)")
        #expect(mae < artboard.limit, "\(artboard.name) @2x: MAE \(mae)")
    }
}
