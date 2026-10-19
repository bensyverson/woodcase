//
//  WriteRoutingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditPlanner/routeWrites(_:at:in:)``: where an editor's computed values for what is
/// drawn are stored — the node's own storage, an instance's `ref` node for its `common`
/// properties, a root override for the rest of an instance root, and an override on the
/// outermost instance for anything inside one, nested instances included.
@MainActor
struct WriteRoutingTests {
    /// `Board` holds the rectangle `Card` and `Chip`, an instance of `Button`. `Button`
    /// is a free frame holding the text `Label`, `Ico` (an instance of `Glyph`, whose one
    /// child is `Dot`) and `Row`, a horizontal stack placing `Item`.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 1000, "height": 800, "layout": "none",
          "children": [
          { "type": "rectangle", "id": "Card", "x": 10, "y": 10, "width": 50, "height": 30 },
          { "type": "ref", "id": "Chip", "ref": "Button", "x": 50, "y": 600 }
        ] },
        { "type": "frame", "id": "Button", "reusable": true, "x": 0, "y": 1000, "width": 120, "height": 40,
          "layout": "none", "children": [
          { "type": "text", "id": "Label", "x": 4, "y": 4, "content": "Go", "fontSize": 14 },
          { "type": "ref", "id": "Ico", "ref": "Glyph", "x": 90, "y": 10 },
          { "type": "frame", "id": "Row", "x": 0, "y": 30, "width": 60, "height": 10, "layout": "horizontal",
            "children": [
            { "type": "rectangle", "id": "Item", "width": 10, "height": 10 }
          ] }
        ] },
        { "type": "frame", "id": "Glyph", "reusable": true, "x": 0, "y": 1100, "width": 10, "height": 10,
          "layout": "none", "children": [
          { "type": "rectangle", "id": "Dot", "x": 1, "y": 1, "width": 4, "height": 4 }
        ] }
      ]
    }
    """

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(Self.json.utf8)))
    }

    private func apply(_ operations: [EditOperation], to document: EditableDocument) throws {
        for operation in operations {
            try document.apply(operation)
        }
    }

    private func refData(_ id: String, in document: EditableDocument) -> PenNode.RefData? {
        guard case let .ref(data)? = document.node(id: id)?.kind else { return nil }
        return data
    }

    // MARK: - Own storage

    @Test("A plain node takes every property as one write on itself")
    func plainNode() throws {
        let doc = try document()
        let properties: [String: AnyCodable] = ["common.x": 5, "kind.width": 60]
        let operations = try EditPlanner.routeWrites(properties, at: .node(id: "Card"), in: doc)
        #expect(operations == [.setProperties(EditOperation.SetProperties(nodeID: "Card", properties: properties))])
    }

    @Test("Nothing to write is no edits")
    func empty() throws {
        let doc = try document()
        #expect(try EditPlanner.routeWrites([:], at: .node(id: "Card"), in: doc).isEmpty)
        #expect(try EditPlanner.routeWrites([:], at: .node(id: "Chip"), in: doc).isEmpty)
    }

    @Test("A deep metadata key on a plain node is folded onto the metadata it carries")
    func deepMetadataFolds() throws {
        let doc = try document()
        let operations = try EditPlanner.routeWrites(
            ["common.metadata.woodcase.strokeDash": [4, 2]], at: .node(id: "Card"), in: doc
        )
        try apply(operations, to: doc)
        #expect(doc.node(id: "Card")?.strokeDash?.lengths == [4, 2])
        #expect(operations.allSatisfy { operation in
            guard case let .setProperties(set) = operation else { return false }
            return !set.properties.keys.contains("common.metadata.woodcase.strokeDash")
        })
    }

    // MARK: - Instance roots

    @Test("An instance root's x and y are its ref node's own")
    func instanceRootPosition() throws {
        let doc = try document()
        let properties: [String: AnyCodable] = ["common.x": 5, "common.y": 6]
        let operations = try EditPlanner.routeWrites(properties, at: .node(id: "Chip"), in: doc)
        #expect(operations == [.setProperties(EditOperation.SetProperties(nodeID: "Chip", properties: properties))])
    }

    @Test("An instance root's size is a root override, and the component is unchanged")
    func instanceRootSize() throws {
        let doc = try document()
        let component = doc.node(id: "Button")
        let operations = try EditPlanner.routeWrites(["kind.width": 240], at: .node(id: "Chip"), in: doc)
        #expect(try operations == EditPlanner.plan(.override(["kind.width": 240]), at: .node(id: "Chip"), in: doc).operations)
        try apply(operations, to: doc)
        #expect(refData("Chip", in: doc)?.rootOverrides?["width"] == 240)
        #expect(doc.node(id: "Button") == component)
    }

    @Test("A move and a resize of an instance root split between the ref and its root override")
    func instanceRootSplit() throws {
        let doc = try document()
        let operations = try EditPlanner.routeWrites(
            ["common.x": 5, "kind.width": 240], at: .node(id: "Chip"), in: doc
        )
        #expect(operations.first == .setProperties(EditOperation.SetProperties(nodeID: "Chip", properties: ["common.x": 5])))
        try apply(operations, to: doc)
        #expect(doc.node(id: "Chip")?.common.x == .literal(5))
        #expect(refData("Chip", in: doc)?.rootOverrides?["width"] == 240)
        #expect(refData("Chip", in: doc)?.rootOverrides?["x"] == nil)
    }

    // MARK: - Inside instances

    @Test("A node inside an instance is an override on the instance, x and y included")
    func instanceDescendant() throws {
        let doc = try document()
        let label = doc.node(id: "Label")
        let operations = try EditPlanner.routeWrites(
            ["common.x": 8, "kind.fontSize": 20],
            at: .instanceDescendant(refID: "Chip", descendantKey: "Label"), in: doc
        )
        try apply(operations, to: doc)
        #expect(refData("Chip", in: doc)?.descendants?["Label"]?.properties["fontSize"] == 20)
        #expect(refData("Chip", in: doc)?.descendants?["Label"]?.properties["x"] == 8)
        #expect(doc.node(id: "Label") == label)
    }

    @Test("A nested instance's root, and a node inside it, are overrides on the outermost instance")
    func nestedInstance() throws {
        let doc = try document()
        let glyph = doc.node(id: "Glyph")
        let ico = doc.node(id: "Ico")
        try apply(
            EditPlanner.routeWrites(
                ["common.x": 3, "kind.width": 30],
                at: .instanceDescendant(refID: "Chip", descendantKey: "Ico"), in: doc
            ),
            to: doc
        )
        try apply(
            EditPlanner.routeWrites(
                ["kind.width": 8], at: .instanceDescendant(refID: "Chip", descendantKey: "Ico/Dot"), in: doc
            ),
            to: doc
        )
        let descendants = refData("Chip", in: doc)?.descendants
        #expect(descendants?["Ico"]?.properties["x"] == 3)
        #expect(descendants?["Ico"]?.properties["width"] == 30)
        #expect(descendants?["Ico/Dot"]?.properties["width"] == 8)
        #expect(doc.node(id: "Glyph") == glyph)
        #expect(doc.node(id: "Ico") == ico)
    }

    @Test("An x the instance's layout would ignore is refused, as the planner refuses it")
    func refusal() throws {
        let doc = try document()
        #expect(throws: EditRefusal.self) {
            try EditPlanner.routeWrites(
                ["common.x": 5], at: .instanceDescendant(refID: "Chip", descendantKey: "Item"), in: doc
            )
        }
    }
}
