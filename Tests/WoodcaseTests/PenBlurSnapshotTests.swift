import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins background blur and layer blur against Pen 1.2.14's own exports.
///
/// `render-background-blur.pen` (format 2.19, authored here) has four artboards:
///
/// - `flip`: red and blue halves under a green band along the top, with a radius-20 glass
///   over them that overlaps the band — asymmetric top to bottom, so a mirrored backdrop
///   shows.
/// - `r8`: the same halves with the band along the bottom, under a rounded radius-8 glass.
/// - `no-fill`: a glass with a fully transparent fill and an unfilled ellipse; neither blurs.
/// - `layer-blur`: a red rectangle with a radius-8 layer blur on white.
///
/// The references are Pen's PNG exports at 1x and 2x (`scripts/pen-oracle
/// Tests/WoodcaseTests/Fixtures/render-background-blur.pen --scale 1,2`, `pen` CLI 0.3.9).
/// Pen's blur is a Gaussian of sigma `radius / 2` points on the encoded sRGB values.
struct PenBlurSnapshotTests {
    private static let fixture = "render-background-blur"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// One edge to measure: a row through an artboard, in points.
    struct Edge: CustomTestStringConvertible {
        let artboard: String
        let radius: Double
        let row: Int
        let from: Int
        let through: Int
        /// 0 red, 1 green, 2 blue: a channel that steps across the edge.
        let channel: Int
        /// The largest channel difference from Pen's export allowed at 1x; 3/255 at 2x.
        var toleranceAtOneX = 3

        var testDescription: String {
            "\(artboard) r\(Int(radius))"
        }
    }

    /// The edges measured. At a 4 px sigma (radius 8 at 1x) Pen's own blur is a little wider
    /// than the Gaussian it names — its export fits sigma 4.24 px, while ours is the exact 4 —
    /// so those two profiles differ by up to 5/255; every other edge is within 3/255.
    /// Woodcase keeps the exact Gaussian (standing ruling: more correct than Pen is kept).
    private static let edges = [
        Edge(artboard: "flip", radius: 20, row: 150, from: 70, through: 170, channel: 0),
        Edge(artboard: "r8", radius: 8, row: 120, from: 100, through: 140, channel: 0, toleranceAtOneX: 5),
        Edge(artboard: "layer-blur", radius: 8, row: 80, from: 30, through: 90, channel: 1, toleranceAtOneX: 5),
    ]

    private static func render(_ artboard: String, scale: Int) throws -> PixelGrid {
        let image = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard, in: fixture, fixturesDir: fixturesDir, scale: CGFloat(scale)
        ))
        return try #require(PixelGrid(image))
    }

    private static func reference(_ artboard: String, scale: Int) throws -> CGImage {
        try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(fixture)-\(artboard)@\(scale)x", fixturesDir: fixturesDir
        ))
    }

    @Test("Blur sigma is radius / 2 points at every scale", arguments: edges, [1, 2])
    func sigmaIsHalfTheRadius(edge: Edge, scale: Int) throws {
        let pixels = try Self.render(edge.artboard, scale: scale)
        let profile = pixels.row(
            edge.row * scale, from: edge.from * scale, through: edge.through * scale, channel: edge.channel
        )
        let fit = try #require(EdgeSigmaFit(profile: profile))
        let expected = edge.radius * Double(scale) / 2
        print("Blur sigma \(edge.artboard) @\(scale)x: \(fit.sigma) px, expected \(expected)")
        #expect(abs(fit.sigma / expected - 1) <= 0.10, "\(edge.artboard) @\(scale)x: sigma \(fit.sigma) px")
    }

    @Test("The blurred edge is within a few 255ths of Pen's", arguments: edges, [1, 2])
    func edgeProfileMatchesPen(edge: Edge, scale: Int) throws {
        let ours = try Self.render(edge.artboard, scale: scale)
        let pens = try #require(PixelGrid(Self.reference(edge.artboard, scale: scale)))
        var worst = 0
        for x in (edge.from * scale) ... (edge.through * scale) {
            let a = ours.pixel(x, edge.row * scale)
            let b = pens.pixel(x, edge.row * scale)
            worst = max(worst, (0 ..< 3).map { abs(a[$0] - b[$0]) }.max() ?? 0)
        }
        let tolerance = scale == 1 ? edge.toleranceAtOneX : 3
        print("Blur edge \(edge.artboard) @\(scale)x: worst channel difference \(worst)/255")
        #expect(worst <= tolerance, "\(edge.artboard) @\(scale)x: \(worst)/255")
    }

    /// Each limit is `max(measured × 1.5, measured + 0.25)` over the worse of the two scales,
    /// rounded up to a hundredth, never looser than before; the measured figure sits beside it
    /// (`swift test --filter PenBlurSnapshotTests`, 2026-09-26). `no-fill`'s 0.1 already sits
    /// below the rule's own +0.25 floor over a true 0 and stands unchanged.
    @Test(
        "Each blur artboard matches Pen's render",
        arguments: [
            ("flip", 0.47), // measured 0.214
            ("r8", 0.38), // measured 0.129
            ("no-fill", 0.1), // measured 0.000
            ("layer-blur", 0.5), // measured 0.262 (formula 0.52 would loosen it; kept)
        ], [1, 2]
    )
    func matchesPen(artboard: (name: String, limit: Double), scale: Int) throws {
        let rendered = try #require(try PenSnapshotTestHelpers.renderArtboard(
            named: artboard.name, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(scale)
        ))
        let reference = try Self.reference(artboard.name, scale: scale)
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Blur \(artboard.name) @\(scale)x MAE: \(mae)")
        #expect(mae < artboard.limit, "\(artboard.name) @\(scale)x: MAE \(mae)")
    }
}
