//
//  CodeGenerationNamingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// How ``CodeGeneration`` names a view drawn from a root of any kind: by the rule
/// ``PageAnalyzer`` names a page, whatever the root's kind.
struct CodeGenerationNamingTests {
    /// A document of `json`, a comma-separated list of root node objects, beside a reusable
    /// `Card` and a reusable `Toggle`.
    private static func document(_ json: String) throws -> PenDocument {
        try PenParser.parse(Data("""
        {"version": "2.17", "children": [
            {"id": "card", "name": "Card", "type": "frame", "reusable": true, "width": 40, "height": 40},
            {"id": "toggle", "name": "Toggle", "type": "frame", "reusable": true, "width": 40, "height": 20},
            \(json)
        ]}
        """.utf8))
    }

    /// The type names for `ids` of `document`, in `language`.
    private static func names(_ ids: [String], in document: PenDocument, language: CodeLanguage = .react) throws -> [String] {
        try CodeGeneration.code(for: ids, in: document, language: language).map(\.typeName)
    }

    @Test("A text named like a component is suffixed Page")
    func clashWithComponent() throws {
        let document = try Self.document(#"{"id": "t", "name": "Card", "type": "text", "content": "Hi"}"#)

        #expect(try Self.names(["t"], in: document) == ["CardPage"])
    }

    @Test("Two roots of one name are numbered, in the order asked")
    func duplicatesNumbered() throws {
        let document = try Self.document("""
        {"id": "a", "name": "Label", "type": "text", "content": "A"},
        {"id": "b", "name": "label", "type": "text", "content": "B"}
        """)

        #expect(try Self.names(["a", "b"], in: document) == ["Label", "Label2"])
    }

    @Test("A frame named as a component's state variant is a view of its own name")
    func stateVariantName() throws {
        let document = try Self.document(#"{"id": "off", "name": "Toggle:off", "type": "frame", "width": 40, "height": 20}"#)

        #expect(try Self.names(["off"], in: document) == ["ToggleOff"])
    }

    @Test("A root with no name is named from its id")
    func unnamedRoot() throws {
        let document = try Self.document(#"{"id": "hero", "type": "rectangle", "width": 10, "height": 10}"#)

        #expect(try Self.names(["hero"], in: document) == ["Hero"])
    }

    @Test("A root whose name has no letters or digits is named from its id")
    func emptyName() throws {
        let document = try Self.document(#"{"id": "hero", "name": "--", "type": "rectangle", "width": 10, "height": 10}"#)

        #expect(try Self.names(["hero"], in: document) == ["Hero"])
    }

    @Test("A reserved name takes the Page suffix")
    func reservedName() throws {
        let document = try Self.document(#"{"id": "s", "name": "string", "type": "text", "content": "x"}"#)

        #expect(try Self.names(["s"], in: document) == ["StringPage"])
    }

    @Test("A SwiftUI view named like a SwiftUI type is suffixed Page")
    func swiftUIShadow() throws {
        let document = try Self.document(#"{"id": "t", "name": "Text", "type": "text", "content": "x"}"#)

        #expect(try Self.names(["t"], in: document, language: .swiftUI) == ["TextPage"])
    }

    @Test("Screen/ is dropped from a view's name, as from a page's")
    func screenPrefix() throws {
        let document = try Self.document(#"{"id": "s", "name": "Screen/Settings", "type": "frame", "width": 10, "height": 10}"#)

        #expect(try Self.names(["s"], in: document) == ["Settings"])
    }
}
