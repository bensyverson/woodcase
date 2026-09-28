import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Woodcase

/// Smoke tests that render the woodcase-app fixture through the full pipeline.
///
/// This fixture is a complex, real-world mobile app design with 4 screens,
/// 2 themes (light/dark), nested components, variables, and image fills.
/// These tests verify the renderer handles all of this without crashing,
/// save output PNGs for visual inspection, and compare against Pencil
/// reference exports via MAE.
struct PenWoodcaseAppTests {
    private let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private let outputDir = TestOutputDirectory.url

    init() {
        TestFontRegistration.registerTestFonts()
    }

    private let imageProvider = PenRenderer.fileImageProvider(
        relativeTo: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    )

    /// Renders a screen, saves the output PNG, and compares against the Pencil reference.
    ///
    /// Returns the MAE for informational purposes. The caller asserts the threshold.
    private func renderAndCompare(
        theme: [String: String] = [:],
        screenID: String,
        outputName: String,
        maeLimit: Double
    ) async throws -> (image: CGImage, mae: Double) {
        let document = try loadAndProcess(theme: theme)
        let rects = PenLayoutEngine.layout(document)
        guard let screenRect = rects[screenID] else {
            throw AppTestError.noScreen(screenID)
        }
        let size = CGSize(width: screenRect.width, height: screenRect.height)

        guard let image = PenRenderer.render(
            document,
            layoutRects: rects,
            size: size,
            scale: 2,
            rootNodeID: screenID,
            imageProvider: imageProvider
        ) else {
            throw AppTestError.renderFailed(outputName)
        }

        // Save PNG for visual inspection
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("woodcase-app-\(outputName).png")
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw AppTestError.saveFailed(outputName)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw AppTestError.saveFailed(outputName)
        }
        print("Saved: \(outputURL.path)")

        // Compare against Pencil reference
        let reference = PenSnapshotTestHelpers.loadFixtureImage(
            named: "woodcase-app-\(outputName)", fixturesDir: fixturesDir
        )
        let mae: Double
        if let reference {
            mae = PenSnapshotTestHelpers.meanAbsoluteError(between: image, and: reference)
            print("  \(outputName) MAE vs Pencil: \(String(format: "%.3f", mae))")
        } else {
            mae = .infinity
            print("  \(outputName): no reference image found")
        }

        await MAEReport.shared.record(id: "pencil-\(outputName)", mae: mae, limit: maeLimit)

        return (image, mae)
    }

    enum AppTestError: Error {
        case noScreen(String)
        case renderFailed(String)
        case saveFailed(String)
    }

    // MARK: - Pipeline

    private func loadAndProcess(theme: [String: String] = [:]) throws -> PenDocument {
        let penURL = fixturesDir.appendingPathComponent("woodcase-app.pen")
        let penData = try Data(contentsOf: penURL)
        let parsed = try PenParser.parse(penData)
        let expanded = PenRefExpander.expand(parsed)
        return PenVariableResolver.resolve(expanded, theme: theme)
    }

    // MARK: - Light Mode Tests

    @Test("Home Collection renders and matches Pencil reference")
    func homeCollectionLight() async throws {
        let result = try await renderAndCompare(
            screenID: "GkyjX/ydnjs", outputName: "home-collection", maeLimit: 1.29
        )
        #expect(result.image.width > 0)
        // measured 0.859 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 1.29, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Usage Log renders and matches Pencil reference")
    func usageLogLight() async throws {
        let result = try await renderAndCompare(
            screenID: "NZV2n/tcjjA", outputName: "usage-log", maeLimit: 1.05
        )
        #expect(result.image.width > 0)
        // measured 0.698 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 1.05, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Ratings renders and matches Pencil reference")
    func ratingsLight() async throws {
        let result = try await renderAndCompare(
            screenID: "X1KWu/ifBcZ", outputName: "ratings", maeLimit: 1.60
        )
        #expect(result.image.width > 0)
        // measured 1.065 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 1.60, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Wishlist renders and matches Pencil reference")
    func wishlistLight() async throws {
        let result = try await renderAndCompare(
            screenID: "it5ZZ/XQ4l7", outputName: "wishlist", maeLimit: 2.71
        )
        #expect(result.image.width > 0)
        // measured 1.805 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 2.71, "MAE \(result.mae) exceeds threshold")
    }

    // MARK: - Dark Mode Tests

    @Test("Home Collection (Dark) renders and matches Pencil reference")
    func homeCollectionDark() async throws {
        let result = try await renderAndCompare(
            theme: ["mode": "dark"],
            screenID: "FH8Qz/ydnjs", outputName: "home-collection-dark", maeLimit: 1.34
        )
        #expect(result.image.width > 0)
        // measured 0.890 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 1.34, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Usage Log (Dark) renders and matches Pencil reference")
    func usageLogDark() async throws {
        let result = try await renderAndCompare(
            theme: ["mode": "dark"],
            screenID: "553Ui/tcjjA", outputName: "usage-log-dark", maeLimit: 1.10
        )
        #expect(result.image.width > 0)
        // measured 0.732 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 1.10, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Ratings (Dark) renders and matches Pencil reference")
    func ratingsDark() async throws {
        let result = try await renderAndCompare(
            theme: ["mode": "dark"],
            screenID: "Pui09/ifBcZ", outputName: "ratings-dark", maeLimit: 1.48
        )
        #expect(result.image.width > 0)
        // measured 0.983 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 1.48, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Wishlist (Dark) renders and matches Pencil reference")
    func wishlistDark() async throws {
        let result = try await renderAndCompare(
            theme: ["mode": "dark"],
            screenID: "XmYkF/XQ4l7", outputName: "wishlist-dark", maeLimit: 2.51
        )
        #expect(result.image.width > 0)
        // measured 1.671 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 2.51, "MAE \(result.mae) exceeds threshold")
    }

    // MARK: - Settings Screen Tests

    @Test("Settings renders and matches Pencil reference")
    func settingsLight() async throws {
        let result = try await renderAndCompare(
            screenID: "vD6Pn/BTvzs", outputName: "settings", maeLimit: 0.70
        )
        #expect(result.image.width > 0)
        // measured 0.445 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 0.70, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Settings (Dark) renders and matches Pencil reference")
    func settingsDark() async throws {
        let result = try await renderAndCompare(
            theme: ["mode": "dark"],
            screenID: "pkh1K/BTvzs", outputName: "settings-dark", maeLimit: 0.73
        )
        #expect(result.image.width > 0)
        // measured 0.472 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 0.73, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Settings Compact renders and matches Pencil reference")
    func settingsCompact() async throws {
        let result = try await renderAndCompare(
            theme: ["density": "compact"],
            screenID: "HvIEx/BTvzs", outputName: "settings-compact", maeLimit: 0.70
        )
        #expect(result.image.width > 0)
        // measured 0.444 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 0.70, "MAE \(result.mae) exceeds threshold")
    }

    @Test("Settings Compact (Dark) renders and matches Pencil reference")
    func settingsCompactDark() async throws {
        let result = try await renderAndCompare(
            theme: ["mode": "dark", "density": "compact"],
            screenID: "QGQZC/BTvzs", outputName: "settings-compact-dark", maeLimit: 0.73
        )
        #expect(result.image.width > 0)
        // measured 0.472 (BpaSrF: IBM Plex Sans in Google's variable face, each weight its own instance)
        #expect(result.mae < 0.73, "MAE \(result.mae) exceeds threshold")
    }

    // MARK: - Lab Screen Tests

    @Test("Lab renders and matches Pencil reference")
    func labLight() async throws {
        let result = try await renderAndCompare(
            screenID: "f3f7e/ld7Yp", outputName: "lab", maeLimit: 0.79
        )
        #expect(result.image.width > 0)
        #expect(result.mae < 0.79, "MAE \(result.mae) exceeds threshold") // measured 0.526 (BpaSrF)
    }

    @Test("Lab (Dark) renders and matches Pencil reference")
    func labDark() async throws {
        let result = try await renderAndCompare(
            theme: ["mode": "dark"],
            screenID: "VzViF/ld7Yp", outputName: "lab-dark", maeLimit: 0.96
        )
        #expect(result.image.width > 0)
        #expect(result.mae < 0.96, "MAE \(result.mae) exceeds threshold") // measured 0.639 (BpaSrF)
    }
}
