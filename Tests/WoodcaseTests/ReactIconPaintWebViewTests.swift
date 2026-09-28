// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Renders the React emitted for `render-text-unfilled.pen`'s `gradient` and `image`
    /// boards in WebKit and measures each against Pen's own 2x export.
    ///
    /// Each board is an Inter 44 bold "Ink" and a 56 pt lucide square, both painted with the
    /// board's gradient or image. Pen draws the paint through the icon's glyph over the node's
    /// box; the emitter writes it as an SVG paint server on the icon's `stroke`
    /// (``ReactEmitter/iconPaint(_:family:nodeID:ctx:)``). `ReactHarnessBuilder` stands in a
    /// lucide icon font glyph or an empty `<svg>` for every icon, neither of which takes a
    /// `stroke`, so this suite swaps in the square exactly as lucide-react draws it —
    /// `stroke={color}` and the component's props spread over a 24 × 24 `viewBox`, with its
    /// one `rect` — and tests the emitted code against what the real package renders.
    ///
    /// The text falls back to the page's serif (the harness names Inter's face after its
    /// file), which is most of each board's MAE; a black icon is the "before", measured in
    /// the same run by pointing the icon's stroke back at `currentColor`.
    @Suite("React icon paint WebView", .tags(.webViewRegression), .serialized, .hangGuard)
    @MainActor
    struct ReactIconPaintWebViewTests {
        /// One artboard to render and what to hold it to.
        struct Board: CustomTestStringConvertible {
            /// The artboard's name.
            let name: String
            /// The largest MAE against Pen's export.
            let maeLimit: Double

            var testDescription: String {
                name
            }
        }

        private nonisolated static let fixture = "render-text-unfilled"

        /// Limits follow the margin rule (`project/2026-09-26-mae-margin-rule.md`):
        /// `max(measured × 1.5, measured + 0.25)`, measured 2026-09-27 with
        /// `swift test -j 3 --filter ReactIconPaintWebViewTests`, and re-measured 2026-09-28 with
        /// the full suite once each text's first baseline sat on Pen's whole point (leaf BpaSrF;
        /// 2.123 and 1.975 when the text drew in a serif fallback, 0.408 and 0.377 after).
        nonisolated static let boards: [Board] = [
            Board(name: "gradient", maeLimit: 0.52), // measured 0.267; icon drawn black: 2.709
            Board(name: "image", maeLimit: 0.53), // measured 0.271; icon drawn black: 2.708
        ]

        private static let fixturesDir = WebViewRegressionFixture.fixturesDirectory
        private static let projectRoot = fixturesDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        private static let fontDir = projectRoot.appendingPathComponent("Tests/WoodcaseTests/Fonts")
        private static let scale = 2

        /// lucide-react's `Square`, as its package draws it, declared after the harness's
        /// stub so this one is the one called.
        private static let lucideSquare = """
        function Square({ size = 24, color = "currentColor", strokeWidth = 2, ...props }) {
          return React.createElement("svg", {
            xmlns: "http://www.w3.org/2000/svg", width: size, height: size, viewBox: "0 0 24 24",
            fill: "none", stroke: color, strokeWidth: strokeWidth,
            strokeLinecap: "round", strokeLinejoin: "round", ...props
          }, React.createElement("rect", { width: 18, height: 18, x: 3, y: 3, rx: 2 }));
        }
        """

        private let harness = WebViewTestHarness()

        @Test("An icon's gradient or image is drawn through its glyph, as Pen draws it", arguments: boards)
        func matchesPen(board: Board) async throws {
            let (image, reference) = try await render(board, blackIcon: false)
            let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: image, and: reference)
            let black = try await render(board, blackIcon: true).image
            let blackMAE = PenSnapshotTestHelpers.meanAbsoluteError(between: black, and: reference)
            print("React icon paint \(board.name) MAE (WebView vs Pen): \(String(format: "%.3f", mae)); "
                + "black icon \(String(format: "%.3f", blackMAE))")
            #expect(mae < board.maeLimit, "\(board.name): MAE \(mae)")
            #expect(mae < blackMAE, "\(board.name): the painted icon (\(mae)) is no closer than a black one (\(blackMAE))")
            await MAEReport.shared.record(id: "react-icon-paint-\(board.name)", mae: mae, limit: board.maeLimit)
        }

        // MARK: - Pipeline

        /// Emits the board as a component, renders it in WebKit at 2x, and loads Pen's export.
        private func render(_ board: Board, blackIcon: Bool) async throws -> (image: CGImage, reference: CGImage) {
            TestFontRegistration.registerTestFonts()
            let url = Self.fixturesDir.appendingPathComponent("\(Self.fixture).pen")
            var document = try PenParser.parse(Data(contentsOf: url))
            for index in document.children.indices {
                document.children[index].common.reusable = true
            }
            let components = ComponentAnalyzer.analyze(document)
            let artboard = try #require(document.children.first { $0.common.name == board.name })
            let component = try #require(components.first { $0.id == artboard.id })
            var files = ReactEmitter.emit(document: document, components: components, theme: ThemeAnalyzer.analyze(document)).files
            if blackIcon {
                files = files.map { file in
                    var file = file
                    file.content = file.content.replacing(/stroke="url\(#[a-z0-9-]+\)"/, with: "stroke=\"currentColor\"")
                    return file
                }
            }
            let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
                named: "\(Self.fixture)-\(board.name)", fixturesDir: Self.fixturesDir
            ))

            let width = reference.width / Self.scale
            let height = reference.height / Self.scale
            var html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: component.name,
                viewportWidth: width,
                viewportHeight: height,
                jsRelativePath: "../js",
                imageRelativePath: "../images",
                fontRelativePath: "../../Fonts",
                fontDir: Self.fontDir
            )
            let stub = "function Square("
            #expect(html.contains(stub), "the harness no longer stubs Square as this suite expects")
            html = html.replacingOccurrences(of: stub, with: "\(Self.lucideSquare)\nfunction __harnessSquare(")
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let htmlURL = tmpDir.appendingPathComponent("icon-paint-\(board.name)-\(blackIcon ? "black" : "painted").html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)

            let image = try await harness.render(
                fileURL: htmlURL,
                viewportSize: CGSize(width: width, height: height),
                allowingReadAccessTo: Self.projectRoot
            )
            return (image, reference)
        }
    }

#endif
