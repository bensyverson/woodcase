// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Renders the React emitted for the paint fixtures in a real WebKit page and measures
    /// it against Pen's own 2x exports: where a ramp's stops land (Pen puts them on the
    /// node box), and the whole board's mean absolute error.
    ///
    /// The fixtures are `render-stroke-fills.pen` and `render-text-fills.pen`, whose
    /// artboards are not components; each is marked reusable here so the emitter writes it
    /// as one. The page loads the test fonts, so the text boards draw Inter, at its default
    /// optical size as Pen draws it: `twin-lin-h` measured 3.37 while React wrote no
    /// `font-optical-sizing: none` and WebKit set its 72 pt Inter in the narrower display cut
    /// (leaf Gmh2sB).
    @Suite("React paint WebView", .tags(.webViewRegression), .hangGuard)
    @MainActor
    struct ReactPaintWebViewTests {
        /// One artboard to render and what to hold it to.
        struct Board: CustomTestStringConvertible {
            /// The fixture file, without extension.
            let fixture: String
            /// The artboard's name.
            let name: String
            /// The axis a red→blue ramp runs along, when the paint is one.
            let axis: PenFillDomainTests.Axis?
            /// Where the ramp's stops belong: the node box's edges on `axis`.
            let domain: ClosedRange<Double>?
            /// The largest whole-board MAE against Pen's export, when it is compared.
            let maeLimit: Double?

            var testDescription: String {
                "\(fixture) \(name)"
            }
        }

        private nonisolated static let strokes = "render-stroke-fills"
        private nonisolated static let text = "render-text-fills"

        /// Limits follow the margin rule (`project/2026-09-26-mae-margin-rule.md`):
        /// `max(measured × 1.5, measured + 0.25)`, measured 2026-09-27 with
        /// `swift test -j 3 --filter ReactPaintWebViewTests`. Before, every limit was 1 or 2 and
        /// the text boards had none, because the page loaded no fonts. The text boards were
        /// re-measured the same way with leaves Gmh2sB, 3Xbv46 and RgeMUN: 0.703, 0.307 and
        /// 3.372 before (optical size, line height 1.3).
        nonisolated static let boards: [Board] = [
            Board(fixture: strokes, name: "rect-lin-h-inner", axis: .x, domain: 60 ... 260, maeLimit: 0.28), // measured 0.021
            Board(fixture: strokes, name: "rect-lin-h-center", axis: .x, domain: 60 ... 260, maeLimit: 0.27), // measured 0.019
            Board(fixture: strokes, name: "rect-lin-h-outer", axis: .x, domain: 60 ... 260, maeLimit: 0.27), // measured 0.015
            Board(fixture: strokes, name: "rect-lin-v-outer", axis: .y, domain: 60 ... 180, maeLimit: 0.26), // measured 0.010
            Board(fixture: strokes, name: "rect-lin-h-outer-radius", axis: .x, domain: 60 ... 260, maeLimit: 0.29), // measured 0.036
            Board(fixture: strokes, name: "ellipse-lin-h-outer", axis: .x, domain: 60 ... 260, maeLimit: 0.42), // measured 0.163
            Board(fixture: strokes, name: "path-lin-h-center", axis: .x, domain: 60 ... 260, maeLimit: 0.29), // measured 0.035
            Board(fixture: strokes, name: "frame-perside-lin-h-unset", axis: .x, domain: 60 ... 260, maeLimit: 0.27), // measured 0.016
            Board(fixture: strokes, name: "frame-perside-lin-h-outer", axis: .x, domain: 60 ... 260, maeLimit: 0.27), // measured 0.013
            Board(fixture: strokes, name: "rect-uv-inner", axis: nil, domain: nil, maeLimit: 0.28), // measured 0.022
            Board(fixture: strokes, name: "rect-uv-outer", axis: nil, domain: nil, maeLimit: 0.25), // measured 0.000
            Board(fixture: strokes, name: "path-uv-center", axis: nil, domain: nil, maeLimit: 0.28), // measured 0.030
            Board(fixture: strokes, name: "frame-perside-uv-radius", axis: nil, domain: nil, maeLimit: 0.29), // measured 0.032
            Board(fixture: strokes, name: "rect-stack", axis: nil, domain: nil, maeLimit: 0.30), // measured 0.041
            Board(fixture: strokes, name: "rect-grad-opacity", axis: nil, domain: nil, maeLimit: 0.28), // measured 0.026
            Board(fixture: strokes, name: "rect-radial-center", axis: nil, domain: nil, maeLimit: 0.27), // measured 0.013
            Board(fixture: strokes, name: "rect-uv-fit-outer", axis: nil, domain: nil, maeLimit: 0.25), // measured 0.000
            Board(fixture: text, name: "txt-lin-h-fixed-left", axis: .x, domain: 40 ... 520, maeLimit: 0.32), // measured 0.065
            Board(fixture: text, name: "txt-lin-h-fixed-center", axis: .x, domain: 40 ... 520, maeLimit: 0.29), // measured 0.036
            Board(fixture: text, name: "twin-lin-h", axis: .x, domain: 40 ... 440, maeLimit: 0.44), // measured 0.189
        ]

        private nonisolated static let fixturesDir = WebViewRegressionFixture.fixturesDirectory
        private nonisolated static let projectRoot = fixturesDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        private nonisolated static let fontDir = projectRoot.appendingPathComponent("Tests/WoodcaseTests/Fonts")
        private nonisolated static let scale = 2

        private let harness = WebViewTestHarness()

        @Test("The emitted paint matches Pen's render in WebKit", arguments: boards)
        func matchesPen(board: Board) async throws {
            let (image, reference) = try await render(board)
            if let limit = board.maeLimit {
                let mae = await PenSnapshotTestHelpers.concurrentMeanAbsoluteError(between: image, and: reference)
                print("React paint \(board.name) MAE (WebView vs Pen): \(String(format: "%.3f", mae))")
                #expect(mae < limit, "\(board.name): MAE \(mae)")
                await MAEReport.shared.record(id: "react-paint-\(board.name)", mae: mae, limit: limit)
            }
            if let axis = board.axis, let domain = board.domain {
                let fit = try #require(PenFillDomainTests.RampFit(image, axis: axis, scale: Self.scale))
                print("React paint \(board.name) ramp: \(fit.stop0) → \(fit.stop1), box \(domain)")
                #expect(abs(fit.stop0 - domain.lowerBound) < 1, "\(board.name): stop 0 at \(fit.stop0)")
                #expect(abs(fit.stop1 - domain.upperBound) < 1, "\(board.name): stop 1 at \(fit.stop1)")
            }
        }

        // MARK: - Pipeline

        /// Emits the board as a component, renders it in WebKit at 2x, and loads Pen's export.
        private func render(_ board: Board) async throws -> (image: CGImage, reference: CGImage) {
            let (page, reference) = try await Self.page(board)
            let image = try await harness.render(fileURL: page.url, viewportSize: page.size, allowingReadAccessTo: Self.projectRoot)
            return (image, reference)
        }

        /// Builds the page and loads Pen's export, off the main actor: parsing, emitting and
        /// writing the page are what a render does besides waiting on WebKit.
        @concurrent
        private nonisolated static func page(_ board: Board) async throws -> (page: WebViewTestPage, reference: CGImage) {
            TestFontRegistration.registerTestFonts()
            let url = Self.fixturesDir.appendingPathComponent("\(board.fixture).pen")
            var document = try PenParser.parse(Data(contentsOf: url))
            for index in document.children.indices {
                document.children[index].common.reusable = true
            }
            let components = ComponentAnalyzer.analyze(document)
            let artboard = try #require(document.children.first { $0.common.name == board.name })
            let component = try #require(components.first { $0.id == artboard.id })
            let files = ReactEmitter.emit(document: document, components: components, theme: ThemeAnalyzer.analyze(document)).files
            let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
                named: "\(board.fixture)-\(board.name)", fixturesDir: Self.fixturesDir
            ))

            let width = reference.width / Self.scale
            let height = reference.height / Self.scale
            let html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: component.name,
                viewportWidth: width,
                viewportHeight: height,
                jsRelativePath: "../js",
                imageRelativePath: "../images",
                fontRelativePath: "../../Fonts",
                fontDir: Self.fontDir
            )
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let htmlURL = tmpDir.appendingPathComponent("paint-\(board.fixture)-\(board.name).html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)

            return (WebViewTestPage(url: htmlURL, size: CGSize(width: width, height: height)), reference)
        }
    }

#endif
