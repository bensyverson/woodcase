//
//  PageTypeNameEmitTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The type a page's frame name becomes in every emitter: the designer's camel-case
/// name, inner capitals kept, exactly as a component of that name is written.
struct PageTypeNameEmitTests {
    /// A document holding `frames`, each a small `frame` JSON object.
    private func document(_ frames: [String]) throws -> PenDocument {
        let json = ##"{"version": "2.17", "children": [\##(frames.joined(separator: ", "))]}"##
        return try PenParser.parse(Data(json.utf8))
    }

    private let filledCardPage = ##"{"type": "frame", "id": "P", "name": "FilledCard", "width": 10, "height": 10}"##
    private let filledCardComponent = ##"{"type": "frame", "id": "C", "name": "FilledCard", "reusable": true, "width": 10, "height": 10}"##

    private func react(_ doc: PenDocument) -> [String: String] {
        let result = ReactEmitter.emit(
            document: doc, components: ComponentAnalyzer.analyze(doc), pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc)
        )
        return Dictionary(result.files.map { ($0.path, $0.content) }) { first, _ in first }
    }

    private func swiftUI(_ doc: PenDocument) throws -> [String: String] {
        let result = try SwiftUIEmitter.emit(
            document: doc, components: ComponentAnalyzer.analyze(doc), pages: PageAnalyzer.analyze(doc),
            theme: ThemeAnalyzer.analyze(doc)
        )
        return Dictionary(result.files.map { ($0.path, $0.content) }) { first, _ in first }
    }

    @Test("A page frame named FilledCard emits the React page FilledCard")
    func reactKeepsInnerCapitals() throws {
        let files = try react(document([filledCardPage]))
        let page = try #require(files["pages/FilledCard.tsx"])
        #expect(page.contains("export function FilledCard({ className, style }: FilledCardProps = {}) {"))
    }

    @Test("A page frame named FilledCard emits the SwiftUI view FilledCard")
    func swiftUIKeepsInnerCapitals() throws {
        let files = try swiftUI(document([filledCardPage]))
        let page = try #require(files["Sources/PenUI/Pages/FilledCard.swift"])
        #expect(page.contains("public struct FilledCard: View {"))
    }

    @Test("A React page named like the component it instances is suffixed Page, so its import does not clash")
    func reactPageNamedLikeAComponent() throws {
        let page = ##"{"type": "frame", "id": "P", "name": "FilledCard", "width": 10, "height": 10, "children": [{"type": "ref", "id": "i", "ref": "C"}]}"##
        let files = try react(document([filledCardComponent, page]))
        #expect(files["components/FilledCard.tsx"]?.contains("export function FilledCard(") == true)
        let source = try #require(files["pages/FilledCardPage.tsx"])
        #expect(source.contains("import { FilledCard } from \"../components/FilledCard\";"))
        #expect(source.contains("export function FilledCardPage("))
    }

    @Test("A SwiftUI page named like a component is suffixed Page once")
    func swiftUIPageNamedLikeAComponent() throws {
        let files = try swiftUI(document([filledCardComponent, filledCardPage]))
        #expect(files["Sources/PenUI/Components/FilledCard.swift"]?.contains("public struct FilledCard: View {") == true)
        #expect(files["Sources/PenUI/Pages/FilledCardPage.swift"]?.contains("public struct FilledCardPage: View {") == true)
    }
}
