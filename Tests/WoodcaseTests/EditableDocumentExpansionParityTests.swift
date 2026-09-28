//
//  EditableDocumentExpansionParityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The editing layer's three expansion entry points must agree with
/// ``PenRefExpander`` — the one expander — on every document that has refs.
///
/// They used to disagree: ``EditableDocument/expandRef(nodeID:)`` built a registry
/// holding only the component it was expanding, so a ref *inside* that component
/// had nothing to resolve against and was returned raw.
@MainActor
struct EditableDocumentExpansionParityTests {
    // MARK: - Helpers

    private static var fixturesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }

    private func loadFixture(_ name: String) throws -> PenDocument {
        try PenParser.parse(contentsOf: Self.fixturesURL.appendingPathComponent(name))
    }

    /// The children of a node, whatever kind of container it is.
    private static func children(of node: PenNode) -> [PenNode] {
        switch node.kind {
        case let .frame(data): data.children ?? []
        case let .group(data): data.children ?? []
        default: []
        }
    }

    /// The ids of every node still written as a `ref`, outermost first.
    private static func refIDs(in node: PenNode) -> [String] {
        let own = if case .ref = node.kind { [node.id] } else { [String]() }
        return own + children(of: node).flatMap(refIDs(in:))
    }

    /// The text content of the node with this id, anywhere in the subtree.
    private static func textContent(of id: String, in node: PenNode) -> String? {
        if node.id == id, case let .text(data) = node.kind {
            return data.content?.literalValue
        }
        return children(of: node).lazy.compactMap { textContent(of: id, in: $0) }.first
    }

    /// Every `.pen` fixture that has at least one ref node to expand.
    ///
    /// - Returns: File name → parsed document, in a stable order.
    /// - Throws: Whatever the parser throws on a fixture it cannot read.
    private static func fixturesWithRefs() throws -> [(name: String, document: PenDocument)] {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: fixturesURL.path)
            .filter { $0.hasSuffix(".pen") }
            .sorted()
        return try names.compactMap { name in
            let document = try PenParser.parse(contentsOf: fixturesURL.appendingPathComponent(name))
            let hasRefs = document.children.contains { !refIDs(in: $0).isEmpty }
            return hasRefs ? (name, document) : nil
        }
    }

    // MARK: - Nested refs

    @Test("expandRef expands a ref nested inside the component it materializes")
    func expandRefExpandsNestedRef() throws {
        let editable = try EditableDocument(from: loadFixture("addressing.pen"))

        let result = try editable.expandRef(nodeID: "Nav01")

        #expect(
            Self.refIDs(in: result.expandedNode).isEmpty,
            "Nav01 still holds raw refs: \(Self.refIDs(in: result.expandedNode))"
        )
        // Btn01's own ref to the badge resolves, and Nav01's cross-ref override
        // lands on the node inside it.
        #expect(Self.textContent(of: "Nav01/Bdg01/Cnt01", in: result.expandedNode) == "3")
    }

    @Test("expandSubtree expands refs nested inside the components it pulls in")
    func expandSubtreeExpandsNestedRefs() throws {
        let editable = try EditableDocument(from: loadFixture("addressing.pen"))

        let (expanded, context) = try editable.expandSubtree(rootID: "Dash1")

        #expect(
            Self.refIDs(in: expanded).isEmpty,
            "Dashboard still holds raw refs: \(Self.refIDs(in: expanded))"
        )
        #expect(Self.textContent(of: "Nav01/Bdg01/Cnt01", in: expanded) == "3")
        #expect(context.provenance["Nav01"]?.componentID == "Btn01")
    }

    // MARK: - Parity with the one expander

    @Test("expandedDocument and expandSubtree agree with PenRefExpander on every fixture with refs")
    func entryPointsAgreeWithTheExpander() throws {
        let fixtures = try Self.fixturesWithRefs()
        #expect(!fixtures.isEmpty, "no fixture has a ref node, so this test proves nothing")

        for (name, document) in fixtures {
            let editable = EditableDocument(from: document)

            let (expandedDocument, _) = editable.expandedDocument()
            #expect(
                expandedDocument == PenRefExpander.expand(document),
                "expandedDocument() disagrees with PenRefExpander.expand on \(name)"
            )

            // A subtree read is the same expansion, one root at a time, so the
            // reusables have to stay in the reference for the roots to line up.
            let reference = PenRefExpander.expand(document, for: .canvas)
            for (index, rootID) in editable.rootOrder.enumerated() {
                let (subtree, _) = try editable.expandSubtree(rootID: rootID)
                #expect(
                    subtree == reference.children[index],
                    "expandSubtree(rootID: \(rootID)) disagrees with PenRefExpander.expand on \(name)"
                )
            }
        }
    }
}
