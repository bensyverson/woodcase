import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Woodcase

/// Smoke tests that render fixture .pen files through the full pipeline
/// and save the output PNGs for visual comparison against Pencil's references.
///
/// Output PNGs are saved to a per-process temporary directory (``TestOutputDirectory``)
/// with "-woodcase" suffix.
/// Compare against the Pencil reference PNGs in Tests/WoodcaseTests/Fixtures/.
struct PenRendererSmokeTests {
    /// `render-text` sets Inter, so its logged MAE does not depend on suite order.
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private let outputDir = TestOutputDirectory.url

    /// Runs the full pipeline on a .pen fixture and saves the rendered PNG.
    private func renderFixture(named name: String) throws -> CGImage {
        let penURL = fixturesDir.appendingPathComponent("\(name).pen")
        let penData = try Data(contentsOf: penURL)

        // Parse
        let document = try PenParser.parse(penData)

        // Expand refs first, then resolve variables
        let expanded = PenRefExpander.expand(document)
        let resolved = PenVariableResolver.resolve(expanded)

        // Find the artboard frame (first child)
        guard let artboard = resolved.children.first,
              case .frame = artboard.kind
        else {
            throw SmokeTestError.noArtboard
        }

        // Layout — use the computed artboard rect for canvas size
        let rects = PenLayoutEngine.layout(resolved)
        guard let artboardRect = rects[artboard.id] else {
            throw SmokeTestError.noArtboard
        }
        let size = CGSize(width: artboardRect.width, height: artboardRect.height)

        // Render at 2x to match Pencil's export
        guard let image = PenRenderer.render(
            resolved,
            layoutRects: rects,
            size: size,
            scale: 2
        ) else {
            throw SmokeTestError.renderFailed
        }

        // Save PNG
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("\(name)-woodcase.png")

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SmokeTestError.saveFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw SmokeTestError.saveFailed
        }

        print("Saved: \(outputURL.path)")
        return image
    }

    enum SmokeTestError: Error {
        case noArtboard
        case renderFailed
        case saveFailed
    }

    // MARK: - Smoke Tests

    @Test("Render shapes-and-fills fixture")
    func shapesAndFills() throws {
        let image = try renderFixture(named: "render-shapes-and-fills")
        #expect(image.width > 0)
        #expect(image.height > 0)
        logMAE(rendered: image, fixtureName: "render-shapes-and-fills")
    }

    @Test("Render gradients fixture")
    func gradients() throws {
        let image = try renderFixture(named: "render-gradients")
        #expect(image.width > 0)
        #expect(image.height > 0)
        logMAE(rendered: image, fixtureName: "render-gradients")
    }

    @Test("Render transforms-and-effects fixture")
    func transformsAndEffects() throws {
        let image = try renderFixture(named: "render-transforms-and-effects")
        #expect(image.width > 0)
        #expect(image.height > 0)
        logMAE(rendered: image, fixtureName: "render-transforms-and-effects")
    }

    @Test("Render text fixture")
    func text() throws {
        let image = try renderFixture(named: "render-text")
        #expect(image.width > 0)
        #expect(image.height > 0)
        logMAE(rendered: image, fixtureName: "render-text")
    }

    @Test("Render strokes-and-paths fixture")
    func strokesAndPaths() throws {
        let image = try renderFixture(named: "render-strokes-and-paths")
        #expect(image.width > 0)
        #expect(image.height > 0)
        logMAE(rendered: image, fixtureName: "render-strokes-and-paths")
    }

    @Test("Render clipping-and-gradients fixture")
    func clippingAndGradients() throws {
        let image = try renderFixture(named: "render-clipping-and-gradients")
        #expect(image.width > 0)
        #expect(image.height > 0)
        logMAE(rendered: image, fixtureName: "render-clipping-and-gradients")
    }

    /// Logs the MAE score against the Pencil reference for development visibility.
    private func logMAE(rendered: CGImage, fixtureName: String) {
        guard let reference = PenSnapshotTestHelpers.loadFixtureImage(
            named: fixtureName, fixturesDir: fixturesDir
        ) else { return }
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("  MAE vs Pencil: \(String(format: "%.3f", mae))")
    }
}
