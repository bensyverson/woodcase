// macOS-only: only the WebView regression suite consumes this, and that suite
// is macOS-only because `WebViewTestHarness` links the Mac's system WebKit.
#if os(macOS)

    import Foundation
    @testable import Woodcase

    /// Everything the WebView regression suite derives from `woodcase-app.pen`,
    /// computed once for the whole process.
    ///
    /// All eleven tests in the suite need the same parse, the same variable
    /// resolution, the same ref expansion, the same analysis, the same emitted
    /// React and the same layout — every one a pure function of a fixture file
    /// that cannot change during a run. Recomputing them per test cost 24 s of
    /// the suite's 50 (the ref expansion alone averaged 1.7 s per test), which
    /// was more than the WebView work the suite exists to do.
    ///
    /// Main-actor isolated because the suite is; that is also what makes the
    /// lazy build safe without a lock.
    @MainActor
    struct WebViewRegressionFixture {
        /// The document exactly as parsed — what the code generator analyzes.
        let raw: PenDocument

        /// Variables resolved with refs left intact, so reusable component
        /// definitions still exist under their original IDs. The component
        /// pixel renders draw from this.
        let resolvedOnly: PenDocument

        /// Refs expanded and variables resolved — what the screen pixel
        /// renders draw from.
        let expanded: PenDocument

        /// Every component the analyzer found in ``raw``.
        let components: [ComponentDefinition]

        /// Every page the analyzer found in ``raw``.
        let pages: [PageDefinition]

        /// The theme the analyzer found in ``raw``.
        let theme: ThemeManifest

        /// The React a component comparison loads: emitted from components and
        /// theme alone, which is what `compareComponent` emitted per test.
        let componentFiles: [GeneratedFile]

        /// The React a screen comparison loads: emitted from components, pages
        /// and theme.
        let screenFiles: [GeneratedFile]

        /// Layout of ``resolvedOnly``, keyed by node ID — the component rects.
        let componentRects: [String: PenRect]

        /// Layout of ``expanded``, keyed by node ID — the screen rects.
        let screenRects: [String: PenRect]

        /// Where `woodcase-app.pen` and the HTML fixtures live.
        nonisolated static let fixturesDirectory: URL = .init(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")

        /// The build, memoised. Nothing here is worth recomputing, and a
        /// failure is not cached: a fixture that could not be read should be
        /// re-reported to every test that asks, not silently swallowed once.
        private static var cached: WebViewRegressionFixture?

        /// The one fixture, built on first use.
        ///
        /// - Returns: the shared fixture.
        /// - Throws: whatever reading or parsing `woodcase-app.pen` throws.
        static func shared() throws -> WebViewRegressionFixture {
            if let cached { return cached }
            let built: WebViewRegressionFixture = try WebViewRegressionFixture()
            cached = built
            return built
        }

        /// Runs the whole derivation once.
        ///
        /// - Throws: whatever reading or parsing `woodcase-app.pen` throws.
        private init() throws {
            var watch = PhaseStopwatch("fixture")
            let penURL: URL = Self.fixturesDirectory.appendingPathComponent("woodcase-app.pen")
            let penData: Data = try Data(contentsOf: penURL)
            raw = try PenParser.parse(penData)
            watch.lap("parse")

            resolvedOnly = PenVariableResolver.resolve(raw, theme: [:])
            watch.lap("resolve")

            expanded = PenVariableResolver.resolve(PenRefExpander.expand(raw), theme: [:])
            watch.lap("expand")

            components = ComponentAnalyzer.analyze(raw)
            pages = PageAnalyzer.analyze(raw)
            theme = ThemeAnalyzer.analyze(raw)
            watch.lap("analyze")

            componentFiles = ReactEmitter.emit(
                document: raw,
                components: components,
                theme: theme
            ).files
            screenFiles = ReactEmitter.emit(
                document: raw,
                components: components,
                pages: pages,
                theme: theme
            ).files
            watch.lap("emit")

            componentRects = PenLayoutEngine.layout(resolvedOnly)
            screenRects = PenLayoutEngine.layout(expanded)
            watch.lap("layout")
            watch.total()
        }
    }

#endif
