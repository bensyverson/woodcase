import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Compares Woodcase-rendered output against Pencil reference PNGs using
/// mean absolute error (MAE). Each test renders a fixture through the full
/// pipeline and asserts the MAE is below a threshold.
struct PenSnapshotTests {
    private let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Renders a fixture through the full pipeline at 2x and returns the image.
    ///
    /// - Parameters:
    ///   - name: The fixture filename (without extension).
    ///   - artboardName: Optional artboard name to render. When `nil`, renders the first artboard.
    private func renderFixture(named name: String, artboardName: String? = nil, scale: CGFloat = 2) throws -> CGImage {
        let penURL = fixturesDir.appendingPathComponent("\(name).pen")
        let penData = try Data(contentsOf: penURL)

        let document = try PenParser.parse(penData)
        let expanded = PenRefExpander.expand(document)
        let resolved = PenVariableResolver.resolve(expanded)

        let artboard: PenNode
        if let artboardName {
            guard let found = resolved.children.first(where: {
                $0.common.name == artboardName
            }) else {
                throw SnapshotError.noArtboard
            }
            artboard = found
        } else {
            guard let first = resolved.children.first,
                  case .frame = first.kind
            else {
                throw SnapshotError.noArtboard
            }
            artboard = first
        }

        let rects = PenLayoutEngine.layout(resolved)
        guard let artboardRect = rects[artboard.id] else {
            throw SnapshotError.noArtboard
        }
        let size = CGSize(width: artboardRect.width, height: artboardRect.height)

        guard let image = PenRenderer.render(
            resolved, layoutRects: rects, size: size, scale: scale,
            rootNodeID: artboard.id
        ) else {
            throw SnapshotError.renderFailed
        }
        return image
    }

    enum SnapshotError: Error {
        case noArtboard
        case renderFailed
        case noReferenceImage
    }

    // MARK: - Snapshot Comparison Tests

    @Test("Shapes and fills match Pencil reference within threshold")
    func shapesAndFills() throws {
        let rendered = try renderFixture(named: "render-shapes-and-fills")
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "render-shapes-and-fills", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Shapes and fills MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.016.
        #expect(mae < 0.27)
    }

    @Test("Gradients match Pencil reference within threshold")
    func gradients() throws {
        let rendered = try renderFixture(named: "render-gradients")
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "render-gradients", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Gradients MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.133.
        #expect(mae < 0.39)
    }

    @Test("Transforms and effects match Pencil reference within threshold")
    func transformsAndEffects() throws {
        let rendered = try renderFixture(named: "render-transforms-and-effects")
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "render-transforms-and-effects", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Transforms and effects MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.886.
        #expect(mae < 1.33)
    }

    @Test("Gradient extras (opacity, blend mode) match Pencil reference within threshold")
    func gradientExtras() throws {
        let rendered = try renderFixture(named: "render-gradients", artboardName: "gradient-extras")
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "gradient-extras", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Gradient extras MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.049.
        #expect(mae < 0.30)
    }

    @Test("Strokes and paths match Pencil reference within threshold")
    func strokesAndPaths() throws {
        let rendered = try renderFixture(named: "render-strokes-and-paths")
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "render-strokes-and-paths", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Strokes and paths MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.027 against the export from
        // `scripts/pen-oracle` (pen CLI 0.3.9). The March export it replaced came from an older Pen that
        // left a path's geometry at its SVG offset and scored 5.114.
        #expect(mae < 0.28)
    }

    @Test("Clipping and gradient centers match Pencil reference within threshold")
    func clippingAndGradients() throws {
        let rendered = try renderFixture(named: "render-clipping-and-gradients")
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "render-clipping-and-gradients", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Clipping and gradients MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.060.
        #expect(mae < 0.31)
    }

    // MARK: - Background Blur Snapshot Tests

    @Test("blur1 background blur matches Pencil reference within threshold")
    func blur1BackgroundBlur() throws {
        let rendered = try renderFixture(named: "blur1", scale: 1)
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "blur1", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("blur1 MAE: \(mae)")
        #expect(mae < 0.30) // measured 0.045
    }

    @Test("blur2 background blur with rotated group matches Pencil reference within threshold")
    func blur2BackgroundBlur() throws {
        let rendered = try renderFixture(named: "blur2", scale: 1)
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "blur2", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("blur2 MAE: \(mae)")
        // Correction (2026-09-26): this threshold used to sit at 15.0 for a documented gap
        // between CoreImage's CIGaussianBlur and Pencil's web renderer kernels. Measured today
        // at 0.082 — that gap no longer shows up here — so the bar tightens with the rest.
        #expect(mae < 0.34)
    }

    @Test("blur3 background blur with complex scene matches Pencil reference within threshold")
    func blur3BackgroundBlur() throws {
        let rendered = try renderFixture(named: "blur3", scale: 1)
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "blur3", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("blur3 MAE: \(mae)")
        // Correction (2026-09-26): this threshold used to sit at 25.0 for the same documented
        // blur-kernel gap as blur2 (CoreImage's CIGaussianBlur vs. Pencil's web renderer),
        // reasoned to compound over a larger, more complex scene. Measured today at 0.174 —
        // it does not — so the bar tightens with the rest.
        #expect(mae < 0.43) // measured 0.174
    }

    // MARK: - Group Positioning Snapshot Tests

    @Test("blur2-no-bg group positioning matches Pencil reference within threshold")
    func blur2NoBgGroupPositioning() throws {
        let rendered = try renderFixture(named: "blur2-no-bg", scale: 1)
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "blur2-no-bg", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("blur2-no-bg MAE: \(mae)")
        // max(measured×1.5, measured+0.25); measured 0.000.
        #expect(mae < 0.25)
    }

    @Test("blur3-no-bg group positioning matches Pencil reference within threshold")
    func blur3NoBgGroupPositioning() throws {
        let rendered = try renderFixture(named: "blur3-no-bg", scale: 1)
        let reference = try #require(
            PenSnapshotTestHelpers.loadFixtureImage(named: "blur3-no-bg", fixturesDir: fixturesDir)
        )
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("blur3-no-bg MAE: \(mae)")
        #expect(mae < 0.35) // measured 0.097
    }

    // Text rendering is excluded from pixel comparison — Core Text and Pencil's
    // renderer produce inherently different font rasterization. Text rendering
    // is validated visually via the smoke tests.
}
