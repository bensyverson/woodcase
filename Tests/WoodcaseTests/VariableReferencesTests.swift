//
//  VariableReferencesTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct VariableReferencesTests {
    // MARK: - Helpers

    private func fixture(_ name: String) throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func document(_ json: String) throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(json))
    }

    // MARK: - Node references

    @Test("Every node holding a $name is reported for that variable")
    func reportsNodesHoldingReferences() throws {
        let document = try fixture("parser-variables.pen")
        #expect(document.references(to: "headline").nodeIDs == ["text1"])
        #expect(document.references(to: "primaryColor").nodeIDs == ["text1"])
    }

    @Test("A variable nothing mentions has no references")
    func reportsNoReferences() throws {
        let document = try fixture("parser-variables.pen")
        #expect(document.references(to: "spacing").isEmpty)
        #expect(document.references(to: "showSubtitle").isEmpty)
    }

    @Test("A name no variable defines is not counted as a reference")
    func ignoresUndefinedNames() throws {
        // `woodcase-app.pen` has a text node whose content is the price "$186",
        // which PenValue's own decoder reads as `.variable("186")`.
        let document = try fixture("woodcase-app.pen")
        let index = document.variableReferences()
        #expect(index["186"] == nil)
        let defined = Set((document.variables ?? [:]).keys)
        #expect(Set(index.keys).isSubset(of: defined))
    }

    @Test("A reference inside a ref node's root overrides counts")
    func countsOverrideReferences() throws {
        let document = try document(
            """
            {
              "version": "2.17",
              "variables": { "brand": { "type": "color", "value": "#FF0000" } },
              "children": [
                { "id": "comp1", "type": "frame", "name": "Button", "reusable": true,
                  "children": [] },
                { "id": "use1", "type": "ref", "name": "Use", "ref": "comp1",
                  "fill": "$brand" }
              ]
            }
            """
        )
        #expect(document.references(to: "brand").nodeIDs == ["use1"])
    }

    @Test("Nodes are reported in document order, not id order")
    func reportsInDocumentOrder() throws {
        let document = try document(
            """
            {
              "version": "2.17",
              "variables": { "pad": { "type": "number", "value": 8 } },
              "children": [
                { "id": "zzz", "type": "frame", "name": "First", "gap": "$pad",
                  "children": [
                    { "id": "mmm", "type": "frame", "name": "Inner", "gap": "$pad",
                      "children": [] }
                  ] },
                { "id": "aaa", "type": "frame", "name": "Second", "gap": "$pad",
                  "children": [] }
              ]
            }
            """
        )
        #expect(document.references(to: "pad").nodeIDs == ["zzz", "mmm", "aaa"])
    }

    @Test("A node is counted once however many times it mentions the variable")
    func countsEachNodeOnce() throws {
        let document = try document(
            """
            {
              "version": "2.17",
              "variables": { "pad": { "type": "number", "value": 8 } },
              "children": [
                { "id": "one", "type": "frame", "name": "Box", "gap": "$pad",
                  "opacity": "$pad", "children": [] }
              ]
            }
            """
        )
        #expect(document.references(to: "pad").nodeIDs == ["one"])
    }

    // MARK: - Variable references

    @Test("A variable whose value is $other is reported as referencing it")
    func countsVariableChains() throws {
        let document = try document(
            """
            {
              "version": "2.17",
              "variables": {
                "base": { "type": "color", "value": "#112233" },
                "border": { "type": "color", "value": "$base" }
              },
              "children": []
            }
            """
        )
        let references = document.references(to: "base")
        #expect(references.variableNames == ["border"])
        #expect(references.nodeIDs.isEmpty)
        #expect(!references.isEmpty)
    }

    @Test("A themed variant whose value is $other counts as a reference")
    func countsThemedVariantChains() throws {
        let document = try document(
            """
            {
              "version": "2.17",
              "themes": { "mode": ["light", "dark"] },
              "variables": {
                "ink": { "type": "color", "value": "#000000" },
                "text": { "type": "color", "value": [
                  { "value": "#333333" },
                  { "theme": { "mode": "dark" }, "value": "$ink" }
                ] }
              },
              "children": []
            }
            """
        )
        #expect(document.references(to: "ink").variableNames == ["text"])
    }

    @Test("A variable that mentions itself is not reported as referencing itself")
    func ignoresSelfReference() throws {
        let document = try document(
            """
            {
              "version": "2.17",
              "variables": { "loop": { "type": "string", "value": "$loop" } },
              "children": []
            }
            """
        )
        #expect(document.references(to: "loop").isEmpty)
    }

    // MARK: - The index

    @Test("The index answers for every defined variable, including unreferenced ones")
    func indexCoversEveryVariable() throws {
        let document = try fixture("parser-variables.pen")
        let index = document.variableReferences()
        #expect(index["headline"]?.nodeIDs == ["text1"])
        #expect(index["spacing"] == nil)
        #expect(document.references(to: "spacing").isEmpty)
    }

    @Test("Asking about a variable the document does not define is not an error")
    func unknownVariableHasNoReferences() throws {
        let document = try fixture("parser-variables.pen")
        #expect(document.references(to: "nothingNamedThis").isEmpty)
    }
}
