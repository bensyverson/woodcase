// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Renders the React emitted for `paint-blend-stacks.pen` in a real WebKit page and
    /// measures each board against the CG reference renderer — the codegen gate for paint
    /// blend modes.
    ///
    /// A paint blends only within its node's paints, fills then strokes, as one isolated
    /// group, and only the node's own blend reaches the backdrop (Ben's reading-1 ruling,
    /// 2026-10-20): CSS's `background-blend-mode` model. Each board is a 120 × 120 white
    /// artboard with a colored backdrop rectangle and a blended node over it — a fill stack at
    /// multiply, a lone multiply fill (which blends with nothing), a gradient under a
    /// translucent screen, a multiply stroke over a fill, and a soft-light stack over a
    /// translucent fill; and linear dodge, as a stack, over a translucent fill, from a 50%
    /// source and as a node's blend (leaf 8nwlNY: `mix-blend-mode: plus-lighter`). The
    /// artboards are not components; each is marked reusable here so
    /// the emitter writes it as one.
    @Suite("React paint blend WebView", .tags(.webViewRegression), .hangGuard)
    @MainActor
    struct ReactPaintBlendWebViewTests {
        /// One artboard to render and what to hold it to.
        struct Board: CustomTestStringConvertible {
            /// The artboard's name.
            let name: String
            /// The largest MAE against the CG render.
            let maeLimit: Double

            var testDescription: String {
                name
            }
        }

        private nonisolated static let fixture = "paint-blend-stacks"

        /// Limits follow the margin rule (`project/2026-09-26-mae-margin-rule.md`):
        /// `max(measured × 1.5, measured + 0.25)`, measured 2026-10-20 with
        /// `swift test --filter ReactPaintBlendWebViewTests`.
        nonisolated static let boards: [Board] = [
            Board(name: "stack-multiply", maeLimit: 0.25), // measured 0.000
            Board(name: "lone-multiply", maeLimit: 0.25), // measured 0.000
            Board(name: "gradient-screen", maeLimit: 0.30), // measured 0.049
            Board(name: "stroke-over-fill", maeLimit: 0.25), // measured 0.000
            Board(name: "softlight-stack", maeLimit: 0.44), // measured 0.188
            Board(name: "linear-dodge-stack", maeLimit: 0.25), // measured 0.000
            Board(name: "linear-dodge-node", maeLimit: 0.25), // measured 0.000
            // `plus-lighter` is a Porter–Duff plus: over a 40% fill beneath it, it sums the
            // alphas where the renderer's add keeps source-over's (`PenRendererBlendTests`).
            Board(name: "linear-dodge-translucent", maeLimit: 0.94), // measured 0.625
            // A 50% source: plus-lighter adds αs·Cs, the renderer mixes the add by αs, as
            // Photoshop does. Known, kept: color-dodge measured 6.338 here.
            Board(name: "linear-dodge-half", maeLimit: 4.79), // measured 3.188
        ]

        private nonisolated static let fixturesDir = WebViewRegressionFixture.fixturesDirectory
        private nonisolated static let projectRoot = fixturesDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        private nonisolated static let scale = 2

        private let harness = WebViewTestHarness()

        @Test("The emitted paint blends match the CG render in WebKit", arguments: boards)
        func matchesReference(board: Board) async throws {
            let (page, reference) = try await Self.page(board)
            let image = try await harness.render(fileURL: page.url, viewportSize: page.size, allowingReadAccessTo: Self.projectRoot)
            let mae = await PenSnapshotTestHelpers.concurrentMeanAbsoluteError(between: image, and: reference)
            print("React paint blend \(board.name) MAE (WebView vs CG): \(String(format: "%.3f", mae))")
            #expect(mae < board.maeLimit, "\(board.name): MAE \(mae)")
            await MAEReport.shared.record(id: "react-paint-blend-\(board.name)", mae: mae, limit: board.maeLimit)
        }

        /// Builds the page and renders the CG reference, off the main actor.
        @concurrent
        private nonisolated static func page(_ board: Board) async throws -> (page: WebViewTestPage, reference: CGImage) {
            let url = Self.fixturesDir.appendingPathComponent("\(Self.fixture).pen")
            var document = try PenParser.parse(Data(contentsOf: url))
            for index in document.children.indices {
                document.children[index].common.reusable = true
            }
            let components = ComponentAnalyzer.analyze(document)
            let artboard = try #require(document.children.first { $0.common.name == board.name })
            let component = try #require(components.first { $0.id == artboard.id })
            let files = ReactEmitter.emit(document: document, components: components, theme: ThemeAnalyzer.analyze(document)).files
            let reference = try #require(try PenSnapshotTestHelpers.renderArtboard(
                named: board.name, in: Self.fixture, fixturesDir: Self.fixturesDir, scale: CGFloat(Self.scale)
            ))

            let width = reference.width / Self.scale
            let height = reference.height / Self.scale
            let html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: component.name,
                viewportWidth: width,
                viewportHeight: height,
                jsRelativePath: "../js",
                imageRelativePath: "../images"
            )
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let htmlURL = tmpDir.appendingPathComponent("paint-blend-\(board.name).html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            return (WebViewTestPage(url: htmlURL, size: CGSize(width: width, height: height)), reference)
        }
    }

#endif
