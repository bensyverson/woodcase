// macOS-only: `WebViewTestHarness` is built on SleepyHollow, which links AppKit and the
// Mac's system WebKit.
#if os(macOS)

    import CoreGraphics
    import Foundation
    import Testing
    @testable import Woodcase

    /// Renders a designer's turned, flipped, and turned-and-flipped `:disabled` states in a
    /// real WebKit page and measures each against Pen's own 2x export of the variant.
    ///
    /// The fixture is `react-transform-states.pen`: three button components whose
    /// `:disabled` variant turns (25°), flips (`flipX`) or does both to a free-positioned
    /// child with one rounded corner, so a wrong sign, pivot or order moves pixels. Each
    /// card is drawn three ways: the component at rest (against Pen's base board), the
    /// component disabled (against Pen's variant board), and the variant board emitted as a
    /// component of its own — the path a node that is simply turned takes.
    @Suite("React transform state WebView", .tags(.webViewRegression), .serialized, .hangGuard)
    @MainActor
    struct ReactTransformStateWebViewTests {
        /// One way of drawing one card, and the Pen export it is held to.
        struct Case: CustomTestStringConvertible {
            /// The card's component name.
            let card: String
            /// How the card is drawn.
            let mode: Mode
            /// The largest MAE against Pen's export.
            let maeLimit: Double

            var testDescription: String {
                "\(card) \(mode)"
            }
        }

        /// How a card is drawn.
        enum Mode: String {
            /// The component with no props: the variable's base value.
            case rest
            /// The component with `disabled`: the designer state's value.
            case disabled
            /// The variant board emitted as its own component: the node's own transform.
            case variantBoard
        }

        private nonisolated static let fixture = "react-transform-states"

        /// Limits follow the margin rule (`project/2026-09-26-mae-margin-rule.md`):
        /// `max(measured × 1.5, measured + 0.25)`, measured 2026-09-27 with
        /// `swift test -j 3 --filter ReactTransformStateWebView`. Before the fix the disabled
        /// and variant boards measured 11.0 (turned), 27.1 (flipped) and 26.5 (both).
        nonisolated static let cases: [Case] = [
            Case(card: "TurnedCard", mode: .rest, maeLimit: 0.26), // measured 0.009
            Case(card: "TurnedCard", mode: .disabled, maeLimit: 0.28), // measured 0.026
            Case(card: "TurnedCard", mode: .variantBoard, maeLimit: 0.28), // measured 0.026
            Case(card: "FlippedCard", mode: .rest, maeLimit: 0.26), // measured 0.008
            Case(card: "FlippedCard", mode: .disabled, maeLimit: 0.26), // measured 0.009
            Case(card: "FlippedCard", mode: .variantBoard, maeLimit: 0.26), // measured 0.009
            Case(card: "TurnFlipCard", mode: .rest, maeLimit: 0.27), // measured 0.011
            Case(card: "TurnFlipCard", mode: .disabled, maeLimit: 0.29), // measured 0.039
            Case(card: "TurnFlipCard", mode: .variantBoard, maeLimit: 0.29), // measured 0.039
        ]

        private static let fixturesDir = WebViewRegressionFixture.fixturesDirectory
        private static let projectRoot = fixturesDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        private static let scale = 2

        private let harness = WebViewTestHarness()

        @Test("A designer's turned or flipped state draws as Pen draws it", arguments: cases)
        func matchesPen(testCase: Case) async throws {
            let (image, reference) = try await render(testCase)
            let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: image, and: reference)
            print("React transform state \(testCase.testDescription) MAE (WebView vs Pen): \(String(format: "%.3f", mae))")
            #expect(mae < testCase.maeLimit, "\(testCase.testDescription): MAE \(mae)")
            await MAEReport.shared.record(
                id: "react-transform-\(testCase.card)-\(testCase.mode.rawValue)", mae: mae, limit: testCase.maeLimit
            )
        }

        // MARK: - Pipeline

        /// Emits the card, renders it in WebKit at 2x, and loads Pen's export.
        private func render(_ testCase: Case) async throws -> (image: CGImage, reference: CGImage) {
            let url = Self.fixturesDir.appendingPathComponent("\(Self.fixture).pen")
            var document = try PenParser.parse(Data(contentsOf: url))
            let variantName = "\(testCase.card):disabled"
            let componentName: String
            var props: [String: String] = [:]
            let referenceName: String
            switch testCase.mode {
            case .rest:
                componentName = testCase.card
                referenceName = "\(Self.fixture)-\(testCase.card)"
            case .disabled:
                componentName = testCase.card
                props["disabled"] = "true"
                referenceName = "\(Self.fixture)-\(testCase.card)-disabled"
            case .variantBoard:
                var variant = try #require(document.children.first { $0.common.name == variantName })
                componentName = "\(testCase.card)Variant"
                variant.common.name = componentName
                variant.common.reusable = true
                document.children = [variant]
                referenceName = "\(Self.fixture)-\(testCase.card)-disabled"
            }
            let components = ComponentAnalyzer.analyze(document)
            #expect(components.contains { $0.name == componentName })
            let files = ReactEmitter.emit(document: document, components: components, theme: ThemeAnalyzer.analyze(document)).files
            let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
                named: referenceName, fixturesDir: Self.fixturesDir
            ))

            let width = reference.width / Self.scale
            let height = reference.height / Self.scale
            let html = ReactHarnessBuilder.buildHTML(
                from: files,
                componentName: componentName,
                props: props,
                viewportWidth: width,
                viewportHeight: height,
                jsRelativePath: "../js"
            )
            let tmpDir = Self.fixturesDir.appendingPathComponent("tmp")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let htmlURL = tmpDir.appendingPathComponent("transform-state-\(testCase.card)-\(testCase.mode.rawValue).html")
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
