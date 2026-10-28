// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Rasterizes the SVG export of each render fixture in WebKit and measures it against
    /// the CG reference renderer's picture of the same canvas region.
    ///
    /// WebKit, through the suite's SleepyHollow harness, is the rasterizer: it is on every
    /// Mac without a new dependency, it implements the SVG filters, masks and blend modes
    /// the export writes (Core SVG, the other in-process candidate, does not implement
    /// filters), and it is what most consumers of the SVG — a browser, a web export — will
    /// draw it with. The page inlines the SVG under `@font-face` rules for the test fonts,
    /// because a `<text>` names its family and WebKit runs out of process, where fonts the
    /// test registered are invisible. Every face is loaded before the page says it is ready:
    /// `document.fonts.ready` alone settles before an SVG `<text>` has asked for its face,
    /// and the capture then shows the fallback.
    ///
    /// Each fixture's every top-level node is a root, framed by their union, so one board
    /// per fixture covers all its artboards. Run alone with
    /// `swift test --filter SVGExportWebViewTests`; each MAE is printed and recorded as
    /// `svg-<fixture>` in `performance/mae-test.csv`.
    @Suite("SVG export WebView", .tags(.webViewRegression), .hangGuard)
    @MainActor
    struct SVGExportWebViewTests {
        /// One fixture and the largest MAE its SVG may score against the CG render.
        struct Board: CustomTestStringConvertible {
            /// The fixture file, without extension.
            let fixture: String
            /// The MAE limit, by the margin rule (`project/2026-09-26-mae-margin-rule.md`).
            let limit: Double

            var testDescription: String {
                fixture
            }
        }

        /// Limits follow the margin rule, `max(measured × 1.5, measured + 0.25)`, measured
        /// 2026-10-14 with `swift test --filter SVGExportWebViewTests`. A 0.000 is real, not
        /// a broken comparison: WebKit on macOS paints SVG through Core Graphics, so a path
        /// filled with a color or a gradient lands on the same pixels the CG renderer's
        /// does. What remains is glyph rasterization (Core Text draws a glyph, WebKit fills
        /// it — `render-text`, and `render-icon-placement`, whose icons the SVG outlines),
        /// filter-blurred shadows against CG's own shadow blur, and background blur, which
        /// SVG cannot draw at all (`render-background-blur`, the one large figure).
        nonisolated static let boards: [Board] = [
            Board(fixture: "render-shapes-and-fills", limit: 0.25), // measured 0.000
            Board(fixture: "render-gradients", limit: 0.25), // measured 0.000
            Board(fixture: "render-transforms-and-effects", limit: 0.32), // measured 0.068
            Board(fixture: "render-strokes-and-paths", limit: 0.25), // measured 0.000
            Board(fixture: "render-clipping-and-gradients", limit: 0.25), // measured 0.000
            Board(fixture: "render-arc-donut", limit: 0.25), // measured 0.000
            Board(fixture: "render-stroke-fills", limit: 0.69), // measured 0.439
            Board(fixture: "render-per-side-strokes", limit: 0.25), // measured 0.000
            Board(fixture: "render-painted-lines", limit: 0.25), // measured 0.000
            Board(fixture: "render-rotated-free", limit: 0.30), // measured 0.045
            Board(fixture: "render-free-groups", limit: 0.26), // measured 0.008
            // The two outer-shadow fixtures measured 1.082 and 1.160 after the CG renderer cast
            // a frame's shadow from its children and a line's from its stroke (leaf LB02SZ), and
            // 0.151 and 0.213 once the SVG export cast them too (leaf Fq1RBB, 2026-10-28,
            // `swift test --filter SVGExport`).
            Board(fixture: "render-shadows", limit: 0.40), // measured 0.151
            Board(fixture: "render-inner-shadow-shapes", limit: 0.50), // measured 0.252
            Board(fixture: "render-group-shadows", limit: 0.46), // measured 0.213
            Board(fixture: "render-image-crops", limit: 0.28), // measured 0.029
            Board(fixture: "render-angular-shapes", limit: 0.25), // measured 0.000
            Board(fixture: "render-mesh-gradients", limit: 0.25), // measured 0.000
            Board(fixture: "render-text", limit: 0.49), // measured 0.236
            Board(fixture: "render-text-fills", limit: 0.40), // measured 0.152
            Board(fixture: "render-icon-placement", limit: 0.98), // measured 0.656
            Board(fixture: "render-background-blur", limit: 2.47), // measured 1.646
        ]

        private nonisolated static let fixturesDir = WebViewRegressionFixture.fixturesDirectory
        private nonisolated static let fontDir = fixturesDir.deletingLastPathComponent().appendingPathComponent("Fonts")
        private nonisolated static let scale: CGFloat = 2

        private let harness = WebViewTestHarness()

        @Test("The SVG export rasterizes within MAE of the CG renderer", arguments: boards)
        func matchesCGRenderer(board: Board) async throws {
            let (page, reference) = try await Self.page(board)
            let image = try await harness.render(fileURL: page.url, viewportSize: page.size, allowingReadAccessTo: Self.fixturesDir)
            // Both pictures beside the page, to look at when a figure moves.
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try? PNGEncoder.write(image, to: tmpDir.appendingPathComponent("svg-\(board.fixture)-webkit.png"))
            try? PNGEncoder.write(reference, to: tmpDir.appendingPathComponent("svg-\(board.fixture)-cg.png"))
            let mae = await PenSnapshotTestHelpers.concurrentMeanAbsoluteError(between: image, and: reference)
            print("SVG export \(board.fixture) MAE (WebKit vs CG): \(String(format: "%.3f", mae))")
            #expect(mae < board.limit, "\(board.fixture): MAE \(mae)")
            await MAEReport.shared.record(id: "svg-\(board.fixture)", mae: mae, limit: board.limit)
        }

        /// Exports the fixture's top-level nodes as one SVG, writes a page that inlines it,
        /// and renders the same region with the CG renderer, off the main actor.
        @concurrent
        private nonisolated static func page(_ board: Board) async throws -> (page: WebViewTestPage, reference: CGImage) {
            TestFontRegistration.registerTestFonts()
            let url = fixturesDir.appendingPathComponent("\(board.fixture).pen")
            let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(Data(contentsOf: url))))
            let rects = PenLayoutEngine.layout(document)
            let roots = document.children.map(\.id)
            let images = PenRenderer.imageProvider(relativeTo: fixturesDir)
            let canvas = try #require(PenLayoutEngine.canvasRects(in: document, layoutRects: rects).union(of: roots))
            let bounds = PenRect(
                x: canvas.x.rounded(.down), y: canvas.y.rounded(.down),
                width: (canvas.x + canvas.width).rounded(.up) - canvas.x.rounded(.down),
                height: (canvas.y + canvas.height).rounded(.up) - canvas.y.rounded(.down)
            )

            let reference = try #require(PenRenderer.render(
                document, layoutRects: rects, rootNodeIDs: roots, bounds: bounds, scale: scale, imageProvider: images
            ))
            let svg = try #require(SVGExporter.string(
                document, layoutRects: rects, rootNodeIDs: roots, bounds: bounds, imageProvider: images
            ))
            let fonts = ReactHarnessBuilder.buildFontFaceCSS(relativePath: "../../Fonts", fontDir: fontDir)
            let html = """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <style>
            \(fonts)
            html, body { margin: 0; padding: 0; background: transparent; }
            svg { display: block; }
            </style></head>
            <body>\(svg)
            <script>
            Promise.all(Array.from(document.fonts).map(function (face) { return face.load().catch(function () {}); }))
                .then(function () { window.__READY__ = true; });
            </script>
            </body></html>
            """
            let tmpDir = fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let htmlURL = tmpDir.appendingPathComponent("svg-\(board.fixture).html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            return (WebViewTestPage(url: htmlURL, size: CGSize(width: bounds.width, height: bounds.height)), reference)
        }
    }

    private extension [String: PenRect] {
        /// The union of the rects of `ids`, or `nil` when none has one.
        func union(of ids: [String]) -> PenRect? {
            ids.compactMap { self[$0] }.reduce(nil) { union, rect -> PenRect? in
                guard let union else { return rect }
                let minX = Swift.min(union.x, rect.x), minY = Swift.min(union.y, rect.y)
                let maxX = Swift.max(union.x + union.width, rect.x + rect.width)
                let maxY = Swift.max(union.y + union.height, rect.y + rect.height)
                return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
        }
    }

#endif
