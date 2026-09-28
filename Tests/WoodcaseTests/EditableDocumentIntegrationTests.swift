//
//  EditableDocumentIntegrationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct EditableDocumentIntegrationTests {
    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> PenDocument {
        guard let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: (name as NSString).pathExtension,
            subdirectory: "Fixtures"
        ) else {
            throw FixtureError.notFound(name)
        }
        return try PenParser.parse(contentsOf: url)
    }

    enum FixtureError: Error {
        case notFound(String)
    }

    /// Compares two documents by encoding to sorted-keys JSON.
    private func assertRoundTrip(_ original: PenDocument) throws {
        let editable = EditableDocument(from: original)
        let materialized = editable.materialize()

        let originalJSON = try PenParser.encode(original)
        let materializedJSON = try PenParser.encode(materialized)

        #expect(originalJSON == materializedJSON)
    }

    // MARK: - Fixture Round-Trips

    @Test("Round-trip: nested children")
    func roundTripNestedChildren() throws {
        let doc = try loadFixture("parser-nested-children.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: all node types")
    func roundTripAllNodeTypes() throws {
        let doc = try loadFixture("parser-all-node-types.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: reusable refs")
    func roundTripReusableRef() throws {
        let doc = try loadFixture("parser-reusable-ref.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: themed variables")
    func roundTripThemedVariables() throws {
        let doc = try loadFixture("parser-themed-variables.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: imports")
    func roundTripImports() throws {
        let doc = try loadFixture("parser-imports.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: realistic lower third")
    func roundTripRealisticLowerThird() throws {
        let doc = try loadFixture("parser-realistic-lower-third.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: text content")
    func roundTripTextContent() throws {
        let doc = try loadFixture("parser-text-content.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: deep nesting layout")
    func roundTripDeepNesting() throws {
        let doc = try loadFixture("layout-deep-nesting.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: context hierarchy")
    func roundTripContextHierarchy() throws {
        let doc = try loadFixture("parser-context-hierarchy.pen")
        try assertRoundTrip(doc)
    }

    @Test("Round-trip: unknown properties")
    func roundTripUnknownProperties() throws {
        let doc = try loadFixture("parser-unknown-properties.pen")
        try assertRoundTrip(doc)
    }

    // MARK: - Flatten + Mutate + Materialize

    @Test("Flatten, apply mutation, materialize, verify mutation reflected")
    func flattenMutateMaterialize() throws {
        let doc = try loadFixture("parser-nested-children.pen")
        let editable = EditableDocument(from: doc)

        // Insert a new rectangle at root
        let newNode = PenNode(
            id: "integration-test-node",
            common: PenNodeCommon(name: "Inserted"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100), height: .fixed(50)))
        )
        try editable.apply(.insertNode(EditOperation.InsertNode(node: newNode)))

        let result = editable.materialize()

        // The new node should be at the end of children
        #expect(result.children.last?.id == "integration-test-node")
        #expect(result.children.count == doc.children.count + 1)

        // Re-parse to verify the result is valid
        let encoded = try PenParser.encode(result)
        let reparsed = try PenParser.parse(encoded)
        #expect(reparsed.children.last?.id == "integration-test-node")
    }

    @Test("Complex operation sequence: insert, move, update, delete")
    func complexOperationSequence() throws {
        let doc = try loadFixture("parser-nested-children.pen")
        let editable = EditableDocument(from: doc)

        // 1. Insert a new frame at root
        let frame = PenNode(
            id: "new-frame",
            common: PenNodeCommon(name: "New Frame"),
            kind: .frame(PenNode.FrameData(width: .fixed(400), height: .fixed(300)))
        )
        try editable.apply(.insertNode(EditOperation.InsertNode(node: frame)))

        // 2. Insert a child into the new frame
        let rect = PenNode(
            id: "new-rect",
            common: PenNodeCommon(name: "Child Rect"),
            kind: .rectangle(PenNode.RectangleData(width: .fixed(100), height: .fixed(100)))
        )
        try editable.apply(.insertNode(EditOperation.InsertNode(node: rect, parentID: "new-frame")))

        // 3. Update the rect's common properties
        let updatedCommon = PenNodeCommon(name: "Updated Rect", opacity: .literal(0.5))
        try editable.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "new-rect", common: updatedCommon)))

        // 4. Verify state
        #expect(editable.childIDs(of: "new-frame") == ["new-rect"])
        #expect(editable.node(id: "new-rect")?.common.opacity == .literal(0.5))

        // 5. Delete the frame (cascading)
        try editable.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "new-frame")))
        #expect(editable.node(id: "new-frame") == nil)
        #expect(editable.node(id: "new-rect") == nil)

        // 6. Materialize and verify round-trip integrity of remaining nodes
        let result = editable.materialize()
        let encoded = try PenParser.encode(result)
        let reparsed = try PenParser.parse(encoded)
        #expect(reparsed.children.count == doc.children.count)
    }
}
