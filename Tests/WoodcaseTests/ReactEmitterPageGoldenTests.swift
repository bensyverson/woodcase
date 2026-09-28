//
//  ReactEmitterPageGoldenTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Golden coverage for the `pages/*.tsx` half of the React emitter.
///
/// The component goldens all run through the components-only
/// ``ReactEmitter/emit(document:components:theme:options:diagnostics:)`` overload over
/// `woodcase-app.pen`, whose top-level frames are all `reusable: true` — so `PageAnalyzer`
/// finds no pages there and no golden ever saw an emitted page. That is how pages shipped
/// referencing an undeclared `className` and `style`.
///
/// This suite closes the gap: it runs the same four steps `woodcase generate react` runs
/// (``ComponentAnalyzer``, ``PageAnalyzer``, ``ThemeAnalyzer``, then the
/// pages-carrying `emit` overload) over `Fixtures/pages.pen`, and pins every emitted page
/// file. Regenerate with
/// `UPDATE_GOLDEN=1 swift test --filter "ReactEmitter.*Tests"`, then read the diff.
///
/// ``ReactEmitterPageSignatureTests`` is the companion: it pins the shape of the page
/// signature over synthetic documents. This suite pins whole files from a fixture on disk.
struct ReactEmitterPageGoldenTests {
    // MARK: - Helpers

    /// Run the fixture through the pipeline the CLI runs, and return the emitted files.
    ///
    /// Mirrors `GenerateCommand`'s analyze-then-emit steps exactly, so a divergence
    /// between what the CLI writes and what this suite pins is a change to one of them.
    private func emitFixture() throws -> [GeneratedFile] {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(
            Bundle.module.url(forResource: "pages", withExtension: "pen", subdirectory: "Fixtures")
        )
        let document = try PenParser.parse(contentsOf: url)
        return ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
    }

    /// The emitted page files, in path order.
    private func pageFiles() throws -> [GeneratedFile] {
        try emitFixture()
            .filter { $0.path.hasPrefix("pages/") }
            .sorted { $0.path < $1.path }
    }

    // MARK: - The fixture reaches the emitter as pages

    @Test("The fixture's two non-reusable top-level frames emit two page files")
    func fixtureEmitsTwoPages() throws {
        #expect(try pageFiles().map(\.path) == ["pages/About.tsx", "pages/Home.tsx"])
    }

    // MARK: - Goldens

    @Test("pages/Home.tsx matches its golden")
    func homeMatchesGolden() throws {
        let page = try #require(try pageFiles().first { $0.path == "pages/Home.tsx" })
        try GoldenFile.assert(page.content, name: "Home.tsx", subdirectory: "pages")
    }

    @Test("pages/About.tsx matches its golden")
    func aboutMatchesGolden() throws {
        let page = try #require(try pageFiles().first { $0.path == "pages/About.tsx" })
        try GoldenFile.assert(page.content, name: "About.tsx", subdirectory: "pages")
    }

    // MARK: - An invariant the golden cannot bless

    /// A golden records whatever the emitter did, including a regression, so one check has
    /// to hold independently of it: nothing the emitted markup uses may be free.
    ///
    /// ``ReactEmitterPageSignatureTests`` asserts this over synthetic documents; here it
    /// runs over every page of the fixture, which is the input a real document resembles.
    @Test("Every identifier an emitted page uses is bound in the same file")
    func everyPageBindsWhatItUses() throws {
        for page in try pageFiles() {
            let bound = EmittedSource.boundNames(in: page.content)
            if page.content.contains("className={cn(") {
                #expect(bound.contains("cn"), "\(page.path) uses `cn` but binds it nowhere")
                #expect(bound.contains("className"), "\(page.path) uses `className` but binds it nowhere")
            }
            if page.content.contains("...style,") {
                #expect(bound.contains("style"), "\(page.path) uses `style` but binds it nowhere")
            }
            for match in page.content.matches(of: /<([A-Z]\w*)\b/) {
                let tag = String(match.output.1)
                #expect(bound.contains(tag), "\(page.path) renders <\(tag)> but binds it nowhere")
            }
        }
    }
}
