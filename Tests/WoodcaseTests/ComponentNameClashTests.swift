//
//  ComponentNameClashTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Two reusable components whose frame names make the same type name.
///
/// Each component is one file in a folder shared with the others (`components/<Name>.tsx`,
/// `Components/<Name>.swift`), and a Mac's disk does not tell `FooBar` from `Foobar`, so
/// ``ComponentAnalyzer`` makes every name unique at the source — ignoring case, numbered
/// from 2 in document order — and React, SwiftUI and the manifest all write the name it
/// gives, as they do a page's (``PageAnalyzer``).
struct ComponentNameClashTests {
    /// A document holding `frames`, each a small `frame` JSON object.
    private func document(_ frames: [String]) throws -> PenDocument {
        let json = ##"{"version": "2.17", "children": [\##(frames.joined(separator: ", "))]}"##
        return try PenParser.parse(Data(json.utf8))
    }

    /// A reusable frame `id` named `name`, holding one text so two components differ.
    private func component(_ id: String, _ name: String) -> String {
        ##"{"type": "frame", "id": "\##(id)", "name": "\##(name)", "reusable": true, "width": 10, "height": 10, "##
            + ##""children": [{"type": "text", "id": "\##(id)t", "content": "\##(id)", "fill": "#000000"}]}"##
    }

    /// Every line of `source`, trimmed, so a text node's content can be found as a line.
    private func textLines(_ source: String) -> [String] {
        source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func names(_ doc: PenDocument) -> [String: String] {
        Dictionary(uniqueKeysWithValues: ComponentAnalyzer.analyze(doc).map { ($0.id, $0.name) })
    }

    // MARK: - The analyzer

    @Test("Two components that make the same name are numbered from 2, in document order")
    func numberedInDocumentOrder() throws {
        let doc = try document([component("B", "Card"), component("A", "Component/Card"), component("C", "card")])
        #expect(names(doc) == ["B": "Card", "A": "Card2", "C": "Card3"])
    }

    @Test("Names that differ only in case clash, since their files share a folder on a case-insensitive disk")
    func caseInsensitive() throws {
        let doc = try document([component("A", "FooBar"), component("B", "Foobar")])
        #expect(names(doc) == ["A": "FooBar", "B": "Foobar2"])
    }

    @Test("A number never lands on a name another component already has")
    func numberSkipsTakenNames() throws {
        let doc = try document([component("A", "Card"), component("B", "Card"), component("C", "Card2")])
        let found = names(doc)
        #expect(Set(found.values.map { $0.lowercased() }).count == 3, "\(found)")
        #expect(found["A"] == "Card")
    }

    // MARK: - The emitters

    @Test("React writes each clashing component to its own file, under its own name")
    func reactFiles() throws {
        let doc = try document([component("A", "Card"), component("B", "card")])
        let files = ReactEmitter.emit(
            document: doc, components: ComponentAnalyzer.analyze(doc), theme: ThemeAnalyzer.analyze(doc)
        ).files
        let first = try #require(files.first { $0.path == "components/Card.tsx" })
        let second = try #require(files.first { $0.path == "components/Card2.tsx" })
        #expect(first.content.contains("export function Card("))
        #expect(textLines(first.content).contains("A"), "\(first.content)")
        #expect(textLines(second.content).contains("B"), "\(second.content)")
        #expect(second.content.contains("export function Card2("))
        #expect(files.count { $0.path.hasPrefix("components/Card") } == 2)
    }

    @Test("SwiftUI writes the analyzer's names, numbering nothing twice")
    func swiftUINames() throws {
        let doc = try document([component("A", "FooBar"), component("B", "Foobar")])
        let components = ComponentAnalyzer.analyze(doc)
        let typeNames = SwiftUIEmitter.componentTypeNames(components)
        #expect(typeNames == ["A": "FooBar", "B": "Foobar2"])
        let files = SwiftUIEmitter.emit(
            document: doc, components: components, pages: [], theme: ThemeAnalyzer.analyze(doc)
        ).files
        #expect(files.contains { $0.path == "Sources/PenUI/Components/FooBar.swift" })
        #expect(files.contains { $0.path == "Sources/PenUI/Components/Foobar2.swift" })
    }

    @Test("The manifest lists both components under the names their files carry")
    func manifestNames() throws {
        let doc = try document([component("A", "Card"), component("B", "card")])
        let manifest = ManifestEmitter.emit(
            components: ComponentAnalyzer.analyze(doc), pages: [], theme: ThemeAnalyzer.analyze(doc)
        ).content
        #expect(manifest.contains(#""components\/Card""#), "\(manifest)")
        #expect(manifest.contains(#""components\/Card2""#), "\(manifest)")
    }

    @Test("A ref to the second component names the second component's type")
    func refNamesTheNumberedType() throws {
        let page = ##"{"type": "frame", "id": "P", "name": "Home", "width": 10, "height": 10, "children": [{"type": "ref", "id": "i", "ref": "B"}]}"##
        let doc = try document([component("A", "Card"), component("B", "card"), page])
        let files = ReactEmitter.emit(
            document: doc, components: ComponentAnalyzer.analyze(doc), pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc)
        ).files
        let home = try #require(files.first { $0.path == "pages/Home.tsx" }).content
        #expect(home.contains("<Card2"), "\(home)")
        #expect(home.contains("import { Card2 } from \"../components/Card2\";"), "\(home)")
    }
}
