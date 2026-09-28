// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links
// AppKit and the Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import ImageIO
    import Testing
    import UniformTypeIdentifiers
    @testable import Woodcase

    /// Visual regression tests that compare Woodcase pixel rendering against
    /// the generated React code rendered in a WebView.
    ///
    /// Each test runs the same .pen fixture through two pipelines:
    /// 1. **Woodcase renderer**: Parse → Expand → Resolve → Layout → Render → CGImage
    /// 2. **Code gen pipeline**: Parse → Analyze → Emit → ReactHarnessBuilder → WebView → CGImage
    ///
    /// The two images are compared using MAE (mean absolute error).
    @Suite("WebView Regression", .tags(.webViewRegression), .hangGuard)
    @MainActor
    struct WebViewRegressionTests {
        /// Project root — the directory that `loadFileURL` grants read access to,
        /// covering Tests/ (fixtures, js, images, fonts) and Sources/ (icon fonts).
        private let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        /// Working directory where the harness writes HTML files.
        /// Sits inside Fixtures so relative paths to js/ and images/ are short.
        private let tmpDir = WebViewRegressionFixture.fixturesDirectory
            .appendingPathComponent("tmp")

        private let fontDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fonts")

        private let iconFontDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Woodcase")
            .appendingPathComponent("IconFonts")
            .appendingPathComponent("Fonts")

        private let outputDir = TestOutputDirectory.webViewRegressionURL

        // CSV file for MAE test results, read by scripts/mae-check at commit time.

        private let harness = WebViewTestHarness()

        private let imageProvider = PenRenderer.fileImageProvider(
            relativeTo: WebViewRegressionFixture.fixturesDirectory
        )

        init() {
            TestFontRegistration.registerTestFonts()
        }

        // Limits follow the margin rule (`project/2026-09-26-mae-margin-rule.md`),
        // `max(measured × 1.5, measured + 0.25)`, measured 2026-09-28 with `swift test -j 3`
        // (leaf BpaSrF: the CG side draws IBM Plex Sans in Google's variable face, each
        // weight its own instance, and the page puts each text's first baseline on Pen's
        // whole point; `project/2026-09-28-pen-font-faces.md`).

        // MARK: - Simple Component Tests (Chunk 3)

        @Test("StatCard renders visually similar in both pipelines")
        func statCardVisualMatch() async throws {
            let result = try await compareComponent(named: "StatCard")
            #expect(result.mae < 4.56, "StatCard MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "StatCard", mae: result.mae, limit: 4.56) // measured 3.037
        }

        @Test("ActionButton renders visually similar in both pipelines")
        func actionButtonVisualMatch() async throws {
            let result = try await compareComponent(named: "ActionButton")
            #expect(result.mae < 0.46, "ActionButton MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "ActionButton", mae: result.mae, limit: 0.46) // measured 0.209
        }

        @Test("FavoriteCard renders visually similar in both pipelines")
        func favoriteCardVisualMatch() async throws {
            let result = try await compareComponent(named: "FavoriteCard")
            #expect(result.mae < 1.25, "FavoriteCard MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "FavoriteCard", mae: result.mae, limit: 1.25) // measured 0.829
        }

        @Test("TabBar with selected home renders visually similar in both pipelines")
        func tabBarVisualMatch() async throws {
            // Find the home variant node ID for pixel rendering
            let fixture: WebViewRegressionFixture = try WebViewRegressionFixture.shared()
            let tabBar = try #require(fixture.components.first { $0.name == "TabBar" })
            let homeVariantID = try #require(tabBar.variantIDs["home"])

            let result = try await compareComponent(
                named: "TabBar",
                props: ["selected": "home"],
                pixelRootNodeID: homeVariantID
            )
            #expect(result.mae < 0.91, "TabBar MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "TabBar", mae: result.mae, limit: 0.91) // measured 0.605
        }

        // MARK: - Complex Component Tests (Chunk 4)

        @Test("PencilListItem renders visually similar in both pipelines")
        func pencilListItemVisualMatch() async throws {
            let result = try await compareComponent(named: "PencilListItem")
            #expect(result.mae < 1.74, "PencilListItem MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "PencilListItem", mae: result.mae, limit: 1.74) // measured 1.156
        }

        @Test("TextInput renders visually similar in both pipelines")
        func textInputVisualMatch() async throws {
            let result = try await compareComponent(named: "TextInput")
            #expect(result.mae < 0.47, "TextInput MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "TextInput", mae: result.mae, limit: 0.47) // measured 0.219
        }

        @Test("StatusBar renders visually similar in both pipelines")
        func statusBarVisualMatch() async throws {
            let result = try await compareComponent(named: "StatusBar")
            #expect(result.mae < 0.32, "StatusBar MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "StatusBar", mae: result.mae, limit: 0.32) // measured 0.070
        }

        // MARK: - Full-Screen Tests (Chunk 5)

        @Test("HomeCollection screen renders visually similar")
        func homeCollectionScreenMatch() async throws {
            let result = try await compareScreen(
                screenID: "GkyjX/ydnjs",
                pageName: "HomeCollection",
                outputName: "home-collection"
            )
            #expect(result.mae < 0.93, "HomeCollection screen MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "home-collection", mae: result.mae, limit: 0.93) // measured 0.614
        }

        @Test("Settings screen renders visually similar")
        func settingsScreenMatch() async throws {
            let result = try await compareScreen(
                screenID: "vD6Pn/BTvzs",
                pageName: "ScreenSettings",
                outputName: "settings"
            )
            #expect(result.mae < 0.66, "Settings screen MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "settings", mae: result.mae, limit: 0.66) // measured 0.406
        }

        @Test("Lab screen renders visually similar")
        func labScreenMatch() async throws {
            let result = try await compareScreen(
                screenID: "f3f7e/ld7Yp",
                pageName: "ScreenLab",
                outputName: "lab"
            )
            #expect(result.mae < 0.58, "Lab screen MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "lab", mae: result.mae, limit: 0.58) // measured 0.328
        }

        @Test("Ratings screen renders visually similar")
        func ratingsScreenMatch() async throws {
            let result = try await compareScreen(
                screenID: "X1KWu/ifBcZ",
                pageName: "ScreenRatings",
                outputName: "ratings"
            )
            #expect(result.mae < 0.83, "Ratings screen MAE \(result.mae) exceeds threshold")
            await recordMAE(id: "ratings", mae: result.mae, limit: 0.83) // measured 0.547
        }

        // MARK: - Pipeline Helpers

        private struct ComparisonResult {
            let woodcaseImage: CGImage
            let webViewImage: CGImage
            let mae: Double
        }

        /// Compares a single component rendered via both pipelines.
        /// Viewport dimensions are derived from the component's layout rect.
        private func compareComponent(
            named componentName: String,
            props: [String: String] = [:],
            pixelRootNodeID: String? = nil
        ) async throws -> ComparisonResult {
            var watch = PhaseStopwatch("component:\(componentName)")
            let fixture: WebViewRegressionFixture = try WebViewRegressionFixture.shared()
            watch.lap("fixture")
            let files: [GeneratedFile] = fixture.componentFiles

            guard let componentDef = fixture.components.first(where: { $0.name == componentName }) else {
                throw RegressionError.componentNotFound(componentName)
            }

            // Render via Woodcase pixel renderer (use resolvedOnly — refs not expanded,
            // so reusable component definitions still exist with their original IDs)
            let rootID = pixelRootNodeID ?? componentDef.id
            let rects: [String: PenRect] = fixture.componentRects
            guard let componentRect = rects[rootID] else {
                throw RegressionError.noLayoutRect(componentName)
            }
            let woodcaseSize = CGSize(width: componentRect.width, height: componentRect.height)
            guard let woodcaseImage = PenRenderer.render(
                fixture.resolvedOnly,
                layoutRects: rects,
                size: woodcaseSize,
                scale: 2,
                rootNodeID: rootID,
                imageProvider: imageProvider
            ) else {
                throw RegressionError.renderFailed(componentName)
            }
            watch.lap("penRender")

            // Render via WebView — use only width; let content determine height
            let viewportWidth = Int(componentRect.width)

            let html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: componentName,
                props: props,
                viewportWidth: viewportWidth,
                jsRelativePath: "../js",
                imageRelativePath: "../images",
                fontRelativePath: "../../Fonts",
                fontDir: fontDir,
                iconFontRelativePath: ".",
                iconFontDir: iconFontDir
            )

            // Write HTML to Fixtures/tmp/ for WebView loading and debugging.
            // Copy lucide.ttf alongside so the @font-face relative path stays simple.
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let lucideSrc = iconFontDir.appendingPathComponent("lucide.ttf")
            let lucideDst = tmpDir.appendingPathComponent("lucide.ttf")
            try? FileManager.default.copyItem(at: lucideSrc, to: lucideDst)

            let htmlURL = tmpDir.appendingPathComponent("\(componentName).html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)

            // Also copy to output dir for easy inspection
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let debugURL = outputDir.appendingPathComponent("\(componentName)-debug.html")
            try html.write(to: debugURL, atomically: true, encoding: .utf8)
            watch.lap("html")

            // Use a large initial height; measureContent will resize to actual content height
            let webViewImage = try await harness.render(
                fileURL: htmlURL,
                viewportSize: CGSize(width: CGFloat(viewportWidth), height: 2000),
                allowingReadAccessTo: projectRoot,
                measureContent: true
            )
            watch.lap("webView")

            let mae = await PenSnapshotTestHelpers.concurrentMeanAbsoluteError(between: woodcaseImage, and: webViewImage)
            print("  \(componentName) MAE (Woodcase vs WebView): \(String(format: "%.3f", mae))")
            watch.lap("mae")

            try saveImage(woodcaseImage, named: "\(componentName)-woodcase")
            try saveImage(webViewImage, named: "\(componentName)-webview")
            watch.lap("saveImages")
            watch.total()

            return ComparisonResult(woodcaseImage: woodcaseImage, webViewImage: webViewImage, mae: mae)
        }

        /// Compares a full screen rendered via both pipelines.
        private func compareScreen(
            screenID: String,
            pageName: String,
            outputName: String
        ) async throws -> ComparisonResult {
            var watch = PhaseStopwatch("screen:\(outputName)")
            let fixture: WebViewRegressionFixture = try WebViewRegressionFixture.shared()
            watch.lap("fixture")

            // Woodcase pixel render (fully expanded + resolved)
            let rects: [String: PenRect] = fixture.screenRects
            guard let screenRect = rects[screenID] else {
                throw RegressionError.noLayoutRect(pageName)
            }
            let size = CGSize(width: screenRect.width, height: screenRect.height)
            guard let woodcaseImage = PenRenderer.render(
                fixture.expanded,
                layoutRects: rects,
                size: size,
                scale: 2,
                rootNodeID: screenID,
                imageProvider: imageProvider
            ) else {
                throw RegressionError.renderFailed(pageName)
            }
            watch.lap("penRender")

            let files: [GeneratedFile] = fixture.screenFiles

            let html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: pageName,
                viewportWidth: Int(screenRect.width),
                viewportHeight: Int(screenRect.height),
                jsRelativePath: "../js",
                imageRelativePath: "../images",
                fontRelativePath: "../../Fonts",
                fontDir: fontDir,
                iconFontRelativePath: ".",
                iconFontDir: iconFontDir
            )

            // Write HTML to Fixtures/tmp/ for WebView loading and debugging.
            // Copy lucide.ttf alongside so the @font-face relative path stays simple.
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let lucideSrc = iconFontDir.appendingPathComponent("lucide.ttf")
            let lucideDst = tmpDir.appendingPathComponent("lucide.ttf")
            try? FileManager.default.copyItem(at: lucideSrc, to: lucideDst)

            let htmlURL = tmpDir.appendingPathComponent("\(outputName).html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)

            // Also copy to output dir for easy inspection
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let debugURL = outputDir.appendingPathComponent("\(outputName)-debug.html")
            try html.write(to: debugURL, atomically: true, encoding: .utf8)
            watch.lap("html")

            let webViewImage = try await harness.render(
                fileURL: htmlURL,
                viewportSize: CGSize(width: CGFloat(screenRect.width), height: CGFloat(screenRect.height)),
                allowingReadAccessTo: projectRoot
            )
            watch.lap("webView")

            let mae = await PenSnapshotTestHelpers.concurrentMeanAbsoluteError(between: woodcaseImage, and: webViewImage)
            print("  \(outputName) screen MAE (Woodcase vs WebView): \(String(format: "%.3f", mae))")
            watch.lap("mae")

            try saveImage(woodcaseImage, named: "\(outputName)-woodcase")
            try saveImage(webViewImage, named: "\(outputName)-webview")
            watch.lap("saveImages")
            watch.total()

            return ComparisonResult(woodcaseImage: woodcaseImage, webViewImage: webViewImage, mae: mae)
        }

        // MARK: - Shared Helpers

        private func saveImage(_ image: CGImage, named name: String) throws {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let url = outputDir.appendingPathComponent("\(name).png")
            guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("  Saved: \(url.path)")
        }

        /// Append an MAE result to the CSV file for tracking by scripts/mae-check.
        private func recordMAE(id: String, mae: Double, limit: Double) async {
            await MAEReport.shared.record(id: id, mae: mae, limit: limit)
        }

        enum RegressionError: Error {
            case componentNotFound(String)
            case noLayoutRect(String)
            case renderFailed(String)
        }
    }

    // MARK: - Custom Tag

    extension Tag {
        @Tag static var webViewRegression: Self
    }

#endif
