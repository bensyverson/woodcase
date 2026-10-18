//
//  CodeGenerationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// ``CodeGeneration``: the code for some of a document's nodes, one file per definition,
/// read from `copy-as.pen` — a board of a text, a variable-bound text, a `$9` price, a
/// switched-off text, a swatch and an instance, beside the reusable `Button`.
struct CodeGenerationTests {
    /// The test fonts, registered so React's line pitch is the same in both emits a test
    /// compares, whatever another suite registers meanwhile.
    init() {
        #if canImport(CoreText)
            TestFontRegistration.registerTestFonts()
        #endif
    }

    /// The copy-as fixture, parsed.
    private static func document() throws -> PenDocument {
        try SwiftUIFixtures.document("copy-as")
    }

    /// The fixture with the roots `json`, a comma-separated list of node objects, after its own.
    private static func document(adding json: String) throws -> PenDocument {
        var document = try document()
        let extra = try PenParser.parse(Data("{\"version\": \"2.17\", \"children\": [\(json)]}".utf8))
        document.children += extra.children
        return document
    }

    /// A text root `Body`, id `body2`.
    private static let bodyJSON = ##"{"id": "body2", "name": "Body", "type": "text", "content": "Body copy", "fill": "#000000"}"##

    /// An instance root `Buy` of the fixture's `Button`, id `cta2`.
    private static let buyJSON = #"{"id": "cta2", "name": "Buy", "type": "ref", "ref": "button"}"#

    /// The whole-document emit's files for `document`, by path.
    private static func wholeFiles(_ document: PenDocument, language: CodeLanguage) throws -> [String: String] {
        let components = ComponentAnalyzer.analyze(document)
        let pages = PageAnalyzer.analyze(document)
        let theme = ThemeAnalyzer.analyze(document)
        let result: EmitResult = switch language {
        case .react:
            ReactEmitter.emit(document: document, components: components, pages: pages, theme: theme)
        case .swiftUI:
            try SwiftUIEmitter.emit(document: document, components: components, pages: pages, theme: theme)
        }
        return Dictionary(result.files.map { ($0.path, $0.content) }) { first, _ in first }
    }

    @Test("A component is its own file, the one the whole document's emit writes", arguments: CodeLanguage.allCases)
    func componentMatchesWholeEmit(language: CodeLanguage) throws {
        let document = try Self.document()

        let code = try CodeGeneration.code(for: ["button"], in: document, language: language)

        let only = try #require(code.first)
        #expect(code.count == 1)
        #expect(only.id == "button")
        #expect(only.role == .component)
        // SwiftUI's `Button` would shadow SwiftUI's own.
        #expect(only.typeName == (language == .react ? "Button" : "ButtonView"))
        #expect(try Self.wholeFiles(document, language: language)[only.file.path] == only.file.content)
    }

    @Test("A board is a view, the file the whole document's emit writes for its page", arguments: CodeLanguage.allCases)
    func boardMatchesWholeEmit(language: CodeLanguage) throws {
        let document = try Self.document()

        let code = try CodeGeneration.code(for: ["card"], in: document, language: language)

        let only = try #require(code.first)
        #expect(only.role == .view)
        #expect(only.typeName == "Card")
        #expect(try Self.wholeFiles(document, language: language)[only.file.path] == only.file.content)
    }

    @Test("React paths: components/ for a component, pages/ for a view")
    func reactPaths() throws {
        let code = try CodeGeneration.code(for: ["card", "button"], in: Self.document(), language: .react)

        #expect(code.map(\.file.path) == ["pages/Card.tsx", "components/Button.tsx"])
    }

    @Test("SwiftUI paths: the package's Components/ and Pages/ folders")
    func swiftUIPaths() throws {
        let code = try CodeGeneration.code(for: ["card", "button"], in: Self.document(), language: .swiftUI)

        #expect(code.map(\.file.path) == ["Sources/PenUI/Pages/Card.swift", "Sources/PenUI/Components/ButtonView.swift"])
    }

    @Test("A text root is a view named for its layer")
    func textRoot() throws {
        let document = try Self.document(adding: Self.bodyJSON)

        let react = try #require(CodeGeneration.code(for: ["body2"], in: document, language: .react).first)
        let swiftUI = try #require(CodeGeneration.code(for: ["body2"], in: document, language: .swiftUI).first)

        #expect(react.typeName == "Body")
        #expect(react.file.content.contains("export function Body("))
        #expect(react.file.content.contains("Body copy"))
        #expect(swiftUI.typeName == "Body")
        #expect(swiftUI.file.content.contains("public struct Body: View"))
        #expect(swiftUI.file.content.contains("Text(\"Body copy\")"))
    }

    @Test("A SwiftUI view's header names the kind of node it was drawn from")
    func swiftUIHeaderNamesKind() throws {
        let document = try Self.document(adding: Self.bodyJSON + ", " + Self.buyJSON)

        let code = try CodeGeneration.code(for: ["body2", "cta2", "card"], in: document, language: .swiftUI)
        try #require(code.count == 3)

        #expect(code.map(\.file.content).map { $0.contains("Generated by Woodcase from the \"Body\" text.") } == [true, false, false])
        #expect(code[1].file.content.contains("Generated by Woodcase from the \"Buy\" instance."))
        #expect(code[2].file.content.contains("Generated by Woodcase from the \"Card\" frame."))
    }

    @Test("A rectangle, an icon, a group and an instance at the root are views", arguments: CodeLanguage.allCases)
    func otherKindsAreViews(language: CodeLanguage) throws {
        let document = try Self.document(adding: """
        {"id": "sw2", "name": "Swatch", "type": "rectangle", "width": 40, "height": 40, "fill": "#4F46E5"},
        {"id": "ic", "name": "Star", "type": "icon", "icon": "star", "library": "lucide", "fill": "#000000", "width": 24, "height": 24},
        {"id": "gr", "name": "Cluster", "type": "group", "children": [
            {"id": "gsw", "name": "Inner", "type": "rectangle", "width": 10, "height": 10, "fill": "#000000"}
        ]},
        \(Self.buyJSON)
        """)

        let code = try CodeGeneration.code(for: ["sw2", "ic", "gr", "cta2"], in: document, language: language)
        try #require(code.count == 4)

        #expect(code.map(\.typeName) == ["Swatch", "Star", "Cluster", "Buy"])
        #expect(code.allSatisfy { $0.role == .view })
        let call = language == .react ? "<Button" : "ButtonView("
        #expect(code[3].file.content.contains(call))
    }

    @Test("The result follows the order asked, repeats dropped", arguments: CodeLanguage.allCases)
    func orderAsAsked(language: CodeLanguage) throws {
        let code = try CodeGeneration.code(for: ["button", "card", "button"], in: Self.document(), language: language)

        #expect(code.map(\.id) == ["button", "card"])
    }

    @Test("An id no node has throws nodeNotFound")
    func unknownID() throws {
        let document = try Self.document()

        #expect(throws: CodeGenerationError.nodeNotFound(id: "nope")) {
            try CodeGeneration.code(for: ["nope"], in: document, language: .react)
        }
    }

    @Test("A layer inside a root, not a component, throws notADefinition")
    func nestedLayer() throws {
        let document = try Self.document()

        #expect(throws: CodeGenerationError.notADefinition(id: "body")) {
            try CodeGeneration.code(for: ["body"], in: document, language: .swiftUI)
        }
    }

    @Test("A component defined inside another node is its own component file", arguments: CodeLanguage.allCases)
    func nestedComponent(language: CodeLanguage) throws {
        let document = try Self.document(adding: """
        {"id": "holder", "name": "Holder", "type": "frame", "children": [
            {"id": "chip", "name": "Chip", "type": "frame", "reusable": true, "width": 20, "height": 20}
        ]}
        """)

        let code = try CodeGeneration.code(for: ["chip"], in: document, language: language)

        #expect(code.map(\.role) == [.component])
        #expect(code.map(\.typeName) == ["Chip"])
    }

    @Test("A clip's code is its copied roots' code", arguments: CodeLanguage.allCases)
    func clipOverload(language: CodeLanguage) throws {
        let editable = try EditableDocument(from: Self.document())
        let clip = try PenClip.extract(nodeIDs: ["price", "cta", "swatch"], from: editable)

        let code = try CodeGeneration.code(for: clip, language: language)

        #expect(code.map(\.id) == clip.contentIDs)
        #expect(try code == (CodeGeneration.code(for: clip.contentIDs, in: clip.document, language: language)))
        #expect(code.map(\.typeName) == ["Price", "Swatch", "BuyButton"])
    }

    @Test("A clip's carried definitions are components a caller can ask for", arguments: CodeLanguage.allCases)
    func carriedDefinitions(language: CodeLanguage) throws {
        let editable = try EditableDocument(from: Self.document())
        let clip = try PenClip.extract(nodeIDs: ["cta"], from: editable)
        let carried = clip.document.children.map(\.id).filter { !clip.contentIDs.contains($0) }

        let code = try CodeGeneration.code(for: carried, in: clip.document, language: language)

        #expect(carried == ["button"])
        #expect(code.map(\.role) == [.component])
    }

    @Test("Warnings reach the collector", arguments: CodeLanguage.allCases)
    func diagnostics(language: CodeLanguage) throws {
        // Turned, an instance cannot be a call in SwiftUI; its unmapped override inlines it in React.
        let document = try Self.document(adding: """
        {"id": "turned", "name": "Turned", "type": "ref", "ref": "button", "rotation": 15,
         "descendants": {"label": {"fontSize": 30}}}
        """)
        let collector = PenDiagnosticCollector()

        _ = try CodeGeneration.code(for: ["turned"], in: document, language: language, diagnostics: collector)

        #expect(!collector.diagnostics.isEmpty)
    }
}
