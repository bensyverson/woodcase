//
//  CodeGenerationParityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Every fixture's components and pages, asked for through ``CodeGeneration``, are the
/// files the whole document's emit writes for them, path and text: the two ways in share
/// one emit per definition.
///
/// React reads the line pitch of a font this machine has, so the test fonts are registered
/// first: another suite registering them between the two emits would change one of them.
struct CodeGenerationParityTests {
    init() {
        #if canImport(CoreText)
            TestFontRegistration.registerTestFonts()
        #endif
    }

    /// The fixtures that carry components or pages: every `.pen` under `Fixtures/` that
    /// parses and defines one, by name.
    static let fixtures: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: SwiftUIFixtures.directory.path)) ?? []
        return files.filter { $0.hasSuffix(".pen") }.map { String($0.dropLast(4)) }.sorted().filter { name in
            guard let document = try? SwiftUIFixtures.document(name) else { return false }
            return !ComponentAnalyzer.analyze(document).isEmpty || !PageAnalyzer.analyze(document).isEmpty
        }
    }()

    @Test("Each definition's file is the whole emit's", arguments: fixtures)
    func definitionsMatchWholeEmit(fixture: String) throws {
        let document = try SwiftUIFixtures.document(fixture)
        let components = ComponentAnalyzer.analyze(document)
        // Asked for in document order, the pages are named as the analyzer names them.
        let pageIDs = Set(PageAnalyzer.analyze(document).map(\.id))
        let ids = components.map(\.id) + document.children.map(\.id).filter(pageIDs.contains)
        let theme = ThemeAnalyzer.analyze(document)
        let pages = PageAnalyzer.analyze(document)

        let react = ReactEmitter.emit(document: document, components: components, pages: pages, theme: theme)
        let swiftUI = try SwiftUIEmitter.emit(document: document, components: components, pages: pages, theme: theme)

        for (language, whole) in [(CodeLanguage.react, react), (.swiftUI, swiftUI)] {
            let files = Dictionary(whole.files.map { ($0.path, $0.content) }) { first, _ in first }
            let code = try CodeGeneration.code(for: ids, in: document, language: language)
            #expect(code.count == Set(ids).count, "\(fixture) \(language)")
            for definition in code {
                #expect(files[definition.file.path] == definition.file.content, "\(fixture) \(language) \(definition.file.path)")
            }
        }
    }
}
