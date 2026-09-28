// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Renders the React emitted for `render-text-unfilled.pen` in a real WebKit page and
    /// measures each board against Pen's own 2x export.
    ///
    /// Every board is an Inter 44 bold "Ink" and a lucide square on a #808080 frame, both
    /// carrying the board's fill shape. Pen draws the text and icon of an unfilled board —
    /// no `fill` key, `fill: []`, a disabled colour, a disabled gradient, a transparent
    /// colour — as nothing, and the text and icon of an unparseable enabled solid as black
    /// (`PenUnfilledTextPaintTests` has the full list). The page loads the lucide icon font
    /// and the test fonts the way `WebViewRegressionTests` does, so the text draws Inter, at
    /// the default optical size Pen draws (`font-optical-sizing: none`); every black board
    /// scores the same. The artboards are not components; each is marked reusable here so
    /// the emitter writes it as one.
    @Suite("React unfilled paint WebView", .tags(.webViewRegression), .hangGuard)
    @MainActor
    struct ReactUnfilledPaintWebViewTests {
        /// One artboard to render and what to hold it to.
        struct Board: CustomTestStringConvertible {
            /// The artboard's name.
            let name: String
            /// Whether Pen draws nothing but the board's grey.
            let unfilled: Bool
            /// The largest MAE against Pen's export.
            let maeLimit: Double

            var testDescription: String {
                name
            }
        }

        private nonisolated static let fixture = "render-text-unfilled"

        /// Limits follow the margin rule (`project/2026-09-26-mae-margin-rule.md`):
        /// `max(measured × 1.5, measured + 0.25)`, measured 2026-09-27 with
        /// `swift test -j 3 --filter ReactUnfilledPaintWebViewTests`. Before the fix the no-fill,
        /// empty-list, disabled and disabled-gradient boards measured 7.847 (text and icon drawn
        /// black) and disabled-then-solid 8.059 (both drawn red). The painted boards measured
        /// 3.197 while `ReactHarnessBuilder` named Inter's face after its file and the page drew
        /// the browser's serif; that was not, as this comment used to say, the whole of their
        /// MAE: with Inter loaded they measured 3.275 (leaf vXVtb1), WebKit setting Inter 44 pt
        /// in its display optical size. With `font-optical-sizing: none` and Pen's natural
        /// line height they measured 0.530 (leaves Gmh2sB, 3Xbv46), and with each text's first
        /// baseline on Pen's whole point 0.328 (leaf BpaSrF); the rule sets their limits.
        nonisolated static let boards: [Board] = [
            Board(name: "no-fill", unfilled: true, maeLimit: 0.25), // measured 0.000
            Board(name: "empty-list", unfilled: true, maeLimit: 0.25), // measured 0.000
            Board(name: "disabled", unfilled: true, maeLimit: 0.25), // measured 0.000
            Board(name: "disabled-gradient", unfilled: true, maeLimit: 0.25), // measured 0.000
            Board(name: "transparent", unfilled: true, maeLimit: 0.25), // measured 0.000, before the fix too
            Board(name: "control", unfilled: false, maeLimit: 0.58), // measured 0.328
            Board(name: "bad-hex", unfilled: false, maeLimit: 0.58), // measured 0.328
            Board(name: "missing-variable", unfilled: false, maeLimit: 0.58), // measured 0.328
            Board(name: "disabled-then-solid", unfilled: false, maeLimit: 0.58), // measured 0.327
        ]

        private nonisolated static let fixturesDir = WebViewRegressionFixture.fixturesDirectory
        private nonisolated static let projectRoot = fixturesDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        private nonisolated static let fontDir = projectRoot.appendingPathComponent("Tests/WoodcaseTests/Fonts")
        private nonisolated static let iconFontDir = projectRoot.appendingPathComponent("Sources/Woodcase/IconFonts/Fonts")
        private nonisolated static let scale = 2

        private let harness = WebViewTestHarness()

        @Test("The emitted text and icon draw as Pen draws them", arguments: boards)
        func matchesPen(board: Board) async throws {
            let (image, reference) = try await render(board)
            let mae = await PenSnapshotTestHelpers.concurrentMeanAbsoluteError(between: image, and: reference)
            print("React unfilled \(board.name) MAE (WebView vs Pen): \(String(format: "%.3f", mae))")
            #expect(mae < board.maeLimit, "\(board.name): MAE \(mae)")
            await MAEReport.shared.record(id: "react-unfilled-\(board.name)", mae: mae, limit: board.maeLimit)
            if board.unfilled {
                let inked = try Self.inkedPixels(image)
                #expect(inked == 0, "\(board.name): \(inked) pixels differ from the board's grey")
            }
        }

        @Test("A text and icon whose one solid does not parse draw as #000000 does", arguments: ["bad-hex", "missing-variable"])
        func unparsedSolidDrawsBlack(artboard: String) async throws {
            let rendered = try await render(Board(name: artboard, unfilled: false, maeLimit: 0)).image
            let black = try await render(Board(name: "control", unfilled: false, maeLimit: 0)).image
            let board = try #require(PenFillDomainTests.RGBA(rendered))
            let control = try #require(PenFillDomainTests.RGBA(black))
            #expect(board.bytes == control.bytes, "\(artboard) does not draw as the #000000 control does")
        }

        /// How many pixels differ from the board's own colour, read at its top-left corner,
        /// by more than a rounding step.
        private static func inkedPixels(_ image: CGImage) throws -> Int {
            let pixels = try #require(PenFillDomainTests.RGBA(image))
            let board = pixels.pixel(0, 0)
            var inked = 0
            for py in 0 ..< pixels.height {
                for px in 0 ..< pixels.width {
                    let pixel = pixels.pixel(px, py)
                    let far = abs(Int(pixel.r) - Int(board.r)) > 2 || abs(Int(pixel.g) - Int(board.g)) > 2
                        || abs(Int(pixel.b) - Int(board.b)) > 2
                    if far { inked += 1 }
                }
            }
            return inked
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
            let url = Self.fixturesDir.appendingPathComponent("\(Self.fixture).pen")
            var document = try PenParser.parse(Data(contentsOf: url))
            for index in document.children.indices {
                document.children[index].common.reusable = true
            }
            let components = ComponentAnalyzer.analyze(document)
            let artboard = try #require(document.children.first { $0.common.name == board.name })
            let component = try #require(components.first { $0.id == artboard.id })
            let files = ReactEmitter.emit(document: document, components: components, theme: ThemeAnalyzer.analyze(document)).files
            let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
                named: "\(Self.fixture)-\(board.name)", fixturesDir: Self.fixturesDir
            ))

            let width = reference.width / Self.scale
            let height = reference.height / Self.scale
            let html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: component.name,
                viewportWidth: width,
                viewportHeight: height,
                jsRelativePath: "../js",
                fontRelativePath: "../../Fonts",
                fontDir: Self.fontDir,
                iconFontRelativePath: ".",
                iconFontDir: Self.iconFontDir
            )
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            // The icon font sits beside the page, as `WebViewRegressionTests` puts it; another
            // suite may have copied it already.
            try? FileManager.default.copyItem(
                at: Self.iconFontDir.appendingPathComponent("lucide.ttf"), to: tmpDir.appendingPathComponent("lucide.ttf")
            )
            let htmlURL = tmpDir.appendingPathComponent("unfilled-\(board.name).html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)

            return (WebViewTestPage(url: htmlURL, size: CGSize(width: width, height: height)), reference)
        }
    }

#endif
