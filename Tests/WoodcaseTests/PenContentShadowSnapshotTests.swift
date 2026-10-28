import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins what an outer shadow is cast from against Pen CLI 0.3.13's own exports: the node's
/// painted content, not its box.
///
/// `render-content-shadows.pen` (format 2.21, written by `scripts/gen-content-shadows-fixture`)
/// has one board per case: a frame's fill casts only when it paints (a disabled or fully
/// transparent fill casts nothing, a quarter-alpha one casts at full strength), its stroke casts
/// its band, its children cast through it (clipped when it clips, a line child included, a
/// child's opacity and its own shadow not), and a rectangle follows the same fill and stroke
/// rule. The references are Pen's PNG exports at 1x and 2x (`scripts/pen-oracle
/// Tests/WoodcaseTests/Fixtures/render-content-shadows.pen --scale 1,2`, `pen` CLI 0.3.13).
struct PenContentShadowSnapshotTests {
    private static let fixture = "render-content-shadows"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every board of the fixture, in document order, with its MAE limit.
    ///
    /// Each limit is `max(measured × 1.5, measured + 0.25)` over the worse of the two scales,
    /// rounded up to a hundredth; the measured figure sits beside it, and "was" is the figure
    /// while the renderer cast a frame's box (`swift test --filter PenContentShadowSnapshotTests`,
    /// 2026-10-28, leaf LB02SZ). The two stroke-only rings keep a uniform blur-profile residual
    /// along their whole length, CoreGraphics' Gaussian against Pen's.
    private static let artboards: [(name: String, limit: Double)] = [
        ("filled-overhang", 0.60), // measured 0.350 (was 4.203)
        ("filled-clipped", 0.50), // measured 0.246 (was 0.246)
        ("fillless-clipped", 0.46), // measured 0.203 (was 12.063)
        ("stroke-only", 1.16), // measured 0.768 (was 10.144)
        ("empty", 0.25), // measured 0.000 (was 10.798)
        ("fill-disabled", 0.53), // measured 0.278 (was 15.004)
        ("fill-transparent", 0.53), // measured 0.278 (was 15.004)
        ("translucent-children", 0.47), // measured 0.214 (was 10.863)
        ("child-shadow", 0.36), // measured 0.108 (was 14.718)
        ("line-child", 0.59), // measured 0.333 (was 16.628)
        ("nested-frames", 0.34), // measured 0.087 (was 13.570)
        ("frame-translucent-fill", 0.55), // measured 0.293 (was 4.171)
        ("rect-transparent-fill", 0.25), // measured 0.000 (was 10.798)
        ("rect-stroke-only", 1.16), // measured 0.768 (was 10.144)
    ]

    @Test("The case list names every board of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards.map(\.name))
    }

    @Test("Each content shadow case matches Pen's render", arguments: artboards, [1, 2])
    func matchesPen(artboard: (name: String, limit: Double), scale: Int) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard.name, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard.name)@\(scale)x", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Content shadows \(artboard.name) @\(scale)x MAE: \(mae)")
        #expect(mae < artboard.limit, "\(artboard.name) @\(scale)x: MAE \(mae)")
    }
}
