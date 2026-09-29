//
//  ReactRenderWebViewTests.swift
//  WoodcaseTests
//

// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Emits every renderer fixture board as a React page, renders it in a real WebKit page
    /// and measures it against Pen's own export beside the Core Graphics renderer's MAE on
    /// the same board: the React counterpart of ``SwiftUIRenderTests``.
    ///
    /// A board React can draw as Pen does must land within CG's MAE + 1.0; a board where
    /// React does not yet draw what Pen draws, or draws it better, has its measured MAE
    /// recorded in ``baselines`` with the reason, and fails only when it regresses past
    /// that; a board React already draws better than CG is held to its own MAE in
    /// ``ceilings``. The boards are ``SwiftUIRenderBoard``s — the same fixtures, references and CG
    /// render — without the dark-scheme boards (the harness page has no scheme) and the
    /// two paint fixtures ``ReactPaintWebViewTests`` already holds. The page loads the test
    /// fonts in `Tests/WoodcaseTests/Fonts` — with the committed Google faces in its
    /// `GoogleFonts` folder, which the CG side registers through ``GoogleFontResolver``
    /// (``GoogleFontFacesSnapshotTests/preparation``) — and the bundled icon fonts.
    @Suite("React render WebView", .tags(.webViewRegression), .hangGuard)
    @MainActor
    struct ReactRenderWebViewTests {
        /// Boards held *below* CG + 1.0, keyed like ``baselines``, with the MAE each measured
        /// and why: where React already draws what Pen draws and CG does not yet, CG + 1.0
        /// would not notice React slipping.
        ///
        /// Measured 2026-09-27 with `swift test -j 3 --filter ReactRenderWebViewTests`.
        static let ceilings: [String: (mae: Double, why: String)] = [
            "render-rotated-free-rrect": (0.007, "React turns a free node about its anchor, as Pen does (mkPpjZ); so does CG since nAuBKh"),
            // Measured with leaves Gmh2sB and 3Xbv46: Inter at its default optical size, at
            // Pen's natural pitch (1.244 and 1.536 before).
            "render-rotated-free-rtxtf": (0.084, "turned Inter at Pen's optical size, pitch and baseline; CG 0.144"),
            "render-rotated-free-rtxta": (0.084, "turned Inter at Pen's optical size, pitch and baseline; CG 0.144"),
            // Measured 2026-09-28 with leaf BpaSrF: each text's first baseline on Pen's whole
            // point, by a margin pair (the figure before in brackets; each had gated at CG + 1.0
            // or been baselined).
            "render-rotated-free-rtxts": (0.101, "turned Inter on Pen's baseline (0.167); CG 0.140"),
            "text-natural-line-height": (0.072, "Inter at Pen's natural pitch and baseline (0.195); CG 0.209"),
            "render-text": (0.791, "on Pen's baseline (1.470); CG 0.885"),
            "render-text-line-height-auto-tight": (0.703, "on Pen's baseline (1.641); CG 0.939"),
            "render-text-line-height-loose-wrap": (0.747, "on Pen's baseline (1.591); CG 1.053"),
            "render-text-line-height-stacked": (0.779, "on Pen's baseline (1.466); CG 1.272"),
            "render-text-line-height-tight-wrap": (0.963, "on Pen's baseline (2.370); CG 1.574"),
            "layout-text-auto-overflow": (1.201, "IBM Plex Sans on Pen's baseline (4.374); CG 1.956"),
            "layout-text-fill-beside-fit": (1.503, "IBM Plex Sans on Pen's baseline (4.053); CG 1.816"),
            "layout-text-fixed-width-wrap": (0.964, "IBM Plex Sans on Pen's baseline (2.859); CG 1.382"),
            "layout-text-list-row": (1.304, "IBM Plex Sans on Pen's baseline (3.740); CG 1.773"),
            "layout-text-two-fill": (0.801, "IBM Plex Sans on Pen's baseline (2.976); CG 1.297"),
            "layout-text-vertical-fill": (1.230, "IBM Plex Sans on Pen's baseline (3.685); CG 1.752"),
            // Measured with leaf qtWkxA: the committed Google faces, which the page loads and
            // the CG side registers. WebKit's text sits closer to Pen's than CG's does.
            "render-font-faces-plexmono-400": (1.485, "the Google face itself; CG 2.464"),
            "render-font-faces-plexmono-700": (1.418, "the Google face itself; CG 2.414"),
            "render-font-faces-plexmono-italic": (1.579, "the Google face itself; CG 2.626"),
            "render-font-faces-plexmono-700-italic": (1.515, "the Google face itself; CG 2.539"),
            "render-font-faces-spectral-400": (1.299, "the Google face itself; CG 2.245"),
            "render-font-faces-spectral-700": (1.228, "the Google face itself; CG 2.196"),
            "render-font-faces-spectral-italic": (1.569, "the Google face itself; CG 2.422"),
            "render-font-faces-inter-italic": (1.326, "Inter's italic file; CG 2.466"),
            "render-font-faces-lora-italic": (1.814, "Lora's italic file; CG 2.696"),
            "render-font-faces-instrumentserif-italic": (1.626, "the Google face itself; CG 2.678"),
            // Measured 2026-09-28 with leaves Mu4JsL and AyTAji (35.845 and 2.953 before).
            "render-transforms-and-effects": (0.634, "the turned flex child's slot grown to its turned bounds by margins; CG 0.886"),
            "parser-icon-font": (0.410, "Material Symbols at Pen's weight, 200 when the node sets none; CG 0.887"),
            // Measured 2026-09-28 with leaf 4fZZ38: inner shadows as SVG filters. React draws
            // these tighter than CG, whose icon glyphs and donut shadow edge differ from Pen's
            // (CG 0.393-0.655 since the same leaf gave it icon inner shadows and even-odd clips).
            "render-inner-shadow-shapes-donut": (0.116, "the inner shadow an SVG filter; CG 0.393"),
            "render-inner-shadow-shapes-icon-lucide": (0.051, "the inner shadow an SVG filter over the glyph; CG 0.655"),
            "render-inner-shadow-shapes-icon-material": (0.050, "the inner shadow an SVG filter over the glyph; CG 0.470"),
            "render-inner-shadow-shapes-icon-both": (0.290, "the inner shadow an SVG filter over the glyph; CG 0.408"),
        ]

        /// How far a baselined or ceilinged board may drift before it fails: tighter than the
        /// margin rule's `× 1.5` on a board far from Pen, where half again would hide a regression.
        static let baselineTolerance = 0.5

        /// How far above the CG renderer's MAE a board React can match may land.
        static let fixedBoxMargin = 1.0

        /// The paint fixtures measured here: SwiftUI's, less the stroke and text fills
        /// ``ReactPaintWebViewTests`` measures and the color-scheme fixture, plus the
        /// malformed mesh points.
        nonisolated static let paintFixtures: [String] = SwiftUIFixtures.paintFixtures.filter {
            !["render-text-fills", "render-stroke-fills", "swiftui-color-scheme"].contains($0)
        } + ["render-mesh-malformed-points"]

        /// Fixtures added for the fidelity-gaps survey (`project/2026-09-27-fidelity-gaps.md`),
        /// one exported PNG per artboard, that ``SwiftUIRenderBoard/artboardFixtures`` does not
        /// already hold (`render-rotated-free` and `render-per-side-shapes` are there), and the
        /// probes of React's effect and stroke gaps (leaf Mu4JsL, `scripts/gen-react-gap-fixtures`):
        /// angular gradients on SVG shapes and strokes, inner per-side strokes beside children,
        /// lines with no stroke, and stroke bands on 0×0 and sized boxes with the shadows they cast, with the sizeless frames they grew from;
        /// and turned `fill_container` flex children, whose slot is their turned bounds (leaf ozlazY,
        /// `scripts/gen-turned-fill-fixture`, exported after Pen's settled relayout); and inner
        /// shadows on SVG shapes and icons, and painted strokes on lines (leaf 4fZZ38,
        /// `scripts/gen-react-fx-fixtures`).
        nonisolated static let gapFixtures = [
            "render-font-faces", "render-angular-shapes", "render-inner-sides", "render-unstroked-lines",
            "render-stroke-bands", "render-sizeless-frames", "render-turned-fill", "render-inner-shadow-shapes",
            "render-painted-lines",
        ]

        /// Every board, in a stable order.
        nonisolated static let boards: [SwiftUIRenderBoard] = {
            let single = (SwiftUIFixtures.rendered + SwiftUIRenderBoard.effectFixtures).map { SwiftUIRenderBoard(fixture: $0) }
                + SwiftUIRenderBoard.shapeBoards + SwiftUIRenderBoard.textBoards
            let many = (SwiftUIRenderBoard.artboardFixtures + paintFixtures + gapFixtures).flatMap { fixture in
                let names = (try? PenSnapshotTestHelpers.artboardNames(in: fixture, fixturesDir: SwiftUIFixtures.directory)) ?? []
                return names.map { SwiftUIRenderBoard(fixture: fixture, artboard: $0) }.filter { $0.referenceName != nil }
            }
            return single + many
        }()

        private nonisolated static let fixturesDir = SwiftUIFixtures.directory
        private nonisolated static let projectRoot = fixturesDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        private nonisolated static let fontDir = projectRoot.appendingPathComponent("Tests/WoodcaseTests/Fonts")
        private nonisolated static let iconFontDir = projectRoot.appendingPathComponent("Sources/Woodcase/IconFonts/Fonts")

        /// The pixels per point `WebViewTestHarness` captures at.
        private nonisolated static let captureScale = 2

        private let harness = WebViewTestHarness()

        /// Boards render concurrently. Only the WebKit call runs on the main actor, and
        /// ``WebViewTestHarness/renderSlots`` bounds how many are in it at once; building
        /// the page, the Core Graphics render and both pixel diffs run on the shared pool.
        @Test("Each board renders within its gate", arguments: boards)
        func boardMatchesPen(board: SwiftUIRenderBoard) async throws {
            // The CG side measures and draws Inter and IBM Plex Sans, and the Google faces
            // `render-font-faces` declares, which the page loads from the same files.
            TestFontRegistration.registerTestFonts()
            _ = try await GoogleFontFacesSnapshotTests.preparation.value
            let scale = try board.referenceScale()
            let page = try await Self.page(for: board)
            let capture = try await harness.render(fileURL: page.url, viewportSize: page.size, allowingReadAccessTo: Self.projectRoot)
            let measured = try await Self.measure(board, capture: capture, pageSize: page.size, scale: scale)
            let mae = measured.mae
            let cgMAE = measured.cgMAE
            let size = measured.size
            print("React \(board.id): MAE \(String(format: "%.3f", mae)) (CG \(String(format: "%.3f", cgMAE))) \(size)")

            let limit: Double = if let baseline = Self.baselines[board.id] {
                baseline.mae + Self.baselineTolerance
            } else if let ceiling = Self.ceilings[board.id] {
                min(ceiling.mae + Self.baselineTolerance, cgMAE + Self.fixedBoxMargin)
            } else {
                cgMAE + Self.fixedBoxMargin
            }
            let why = Self.baselines[board.id]?.why.rawValue ?? Self.ceilings[board.id]?.why ?? "CG + \(Self.fixedBoxMargin)"
            #expect(mae <= limit, "\(board.id): React MAE \(mae), CG \(cgMAE), limit \(limit) (\(why)); \(size)")
            await MAEReport.shared.record(id: "react-\(board.id)", mae: mae, limit: limit)
        }

        // MARK: - Pipeline

        /// What one board measured.
        struct Measurement: Friendly {
            /// React's MAE against Pen's export.
            let mae: Double
            /// The Core Graphics renderer's MAE against the same export.
            let cgMAE: Double
            /// The capture's and the reference's sizes, for the log line.
            let size: String
        }

        /// Emits the board's frame as a page and writes it to disk, with the size the frame
        /// lays out at.
        @concurrent
        nonisolated static func page(for board: SwiftUIRenderBoard) async throws -> WebViewTestPage {
            let document = try SwiftUIFixtures.document(board.fixture)
            let root = try #require(board.node(in: document))
            let page = try #require(PageAnalyzer.analyze(document).first { $0.id == root.id }, "\(board.id): no page")
            let files = ReactEmitter.emit(
                document: document,
                components: ComponentAnalyzer.analyze(document),
                pages: [page],
                theme: ThemeAnalyzer.analyze(document)
            ).files
            let pageFile = try #require(files.first { $0.path.hasPrefix("pages/") }, "\(board.id): no page file")
            let pageName = URL(fileURLWithPath: pageFile.path).deletingPathExtension().lastPathComponent

            let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document))
            let rect = try #require(PenLayoutEngine.layout(resolved)[root.id], "\(board.id): no layout")
            let size = CGSize(width: rect.width, height: rect.height)

            let html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: pageName,
                viewportWidth: Int(size.width.rounded(.up)),
                viewportHeight: Int(size.height.rounded(.up)),
                jsRelativePath: "../js",
                imageRelativePath: "../images",
                fontRelativePath: "../../Fonts",
                fontDir: fontDir,
                iconFontRelativePath: "../../../../Sources/Woodcase/IconFonts/Fonts",
                iconFontDir: iconFontDir
            )
            let tmpDir = fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let htmlURL = tmpDir.appendingPathComponent("render-\(board.id).html")
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            return WebViewTestPage(url: htmlURL, size: size)
        }

        /// Brings the capture to the reference's density, renders the board with Core
        /// Graphics, and measures both against Pen's export.
        @concurrent
        nonisolated static func measure(
            _ board: SwiftUIRenderBoard, capture: CGImage, pageSize: CGSize, scale: Int
        ) async throws -> Measurement {
            let referenceName = try #require(board.referenceName)
            let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(named: referenceName, fixturesDir: fixturesDir))
            let react: CGImage = if scale == captureScale {
                capture
            } else {
                try #require(resampled(capture, width: Int((pageSize.width * CGFloat(scale)).rounded()),
                                       height: Int((pageSize.height * CGFloat(scale)).rounded())))
            }
            let cg = try #require(try board.renderCG(scale: CGFloat(scale)))
            return Measurement(
                mae: PenSnapshotTestHelpers.meanAbsoluteError(between: react, and: reference),
                cgMAE: PenSnapshotTestHelpers.meanAbsoluteError(between: cg, and: reference),
                size: "\(react.width)x\(react.height) vs \(reference.width)x\(reference.height)"
            )
        }

        /// `image` drawn at `width` × `height` pixels with high-quality interpolation: a 2x
        /// capture brought down to a 1x reference's density.
        private nonisolated static func resampled(_ image: CGImage, width: Int, height: Int) -> CGImage? {
            guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
    }

#endif
