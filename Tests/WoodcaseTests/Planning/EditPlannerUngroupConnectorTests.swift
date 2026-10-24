//
//  EditPlannerUngroupConnectorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Ungroup (``EditPlanner/planUngroup(groupID:in:layout:)``) removes the wrapper, so a
/// connector attached to the wrapper itself goes with it, in the same edit, as a delete
/// takes one; the connectors attached to its children stay, since the children keep their
/// ids (the integrator's ruling of 2026-10-23, leaf f5bY9O).
@MainActor
struct EditPlannerUngroupConnectorTests {
    /// `Board` holds `Pair`, a group of `G1` and `G2`, and `Lone`. The connectors, at the
    /// top level: `KG` `Pair` → `Lone`; `K1` `G1` → `Lone`; `K12` `G1` → `G2`.
    private static let json = """
    {
      "version": "2.20",
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 800, "height": 600, "layout": "none", "children": [
          { "type": "group", "id": "Pair", "x": 100, "y": 400, "children": [
            { "type": "rectangle", "id": "G1", "x": 0, "y": 0, "width": 20, "height": 20 },
            { "type": "rectangle", "id": "G2", "x": 40, "y": 0, "width": 20, "height": 20 }
          ] },
          { "type": "rectangle", "id": "Lone", "x": 400, "y": 300, "width": 40, "height": 40 }
        ] },
        { "type": "connection", "id": "KG", "source": { "path": "Pair", "anchor": "top" },
          "target": { "path": "Lone", "anchor": "left" } },
        { "type": "connection", "id": "K1", "source": { "path": "G1", "anchor": "top" },
          "target": { "path": "Lone", "anchor": "bottom" } },
        { "type": "connection", "id": "K12", "source": { "path": "G1", "anchor": "right" },
          "target": { "path": "G2", "anchor": "left" } }
      ]
    }
    """

    private func document() throws -> EditableDocument {
        try WrapFixture.document(Self.json)
    }

    /// The connectors still in the document, in document order.
    private func connectors(in document: EditableDocument) -> [String] {
        document.nodeIDsInDocumentOrder().filter { id in
            if case .connection = document.node(id: id)?.kind { return true }
            return false
        }
    }

    @Test("Ungrouping deletes the connector attached to the group, first, and keeps its children's")
    func groupConnectorGoes() throws {
        let document = try document()
        let operations = try EditPlanner.planUngroup(
            groupID: "Pair", in: document, layout: WrapFixture.layout(of: document)
        )

        guard case let .deleteNode(first)? = operations.first else {
            Issue.record("the first operation is not a delete: \(operations)")
            return
        }
        #expect(first.nodeID == "KG")
        try WrapFixture.apply(operations, to: document)
        #expect(connectors(in: document) == ["K1", "K12"])
        #expect(document.node(id: "Pair") == nil)
    }

    @Test("A group with no connector of its own plans exactly as before")
    func noConnector() throws {
        let document = try document()
        try document.apply(.deleteNode(EditOperation.DeleteNode(nodeID: "KG")))
        let operations = try EditPlanner.planUngroup(
            groupID: "Pair", in: document, layout: WrapFixture.layout(of: document)
        )

        let deletes = operations.compactMap { operation -> String? in
            if case let .deleteNode(op) = operation { return op.nodeID }
            return nil
        }
        #expect(deletes == ["Pair"])
    }

    @Test("Undoing the ungroup brings back the group and then its connector")
    func undoRestores() throws {
        let document = try document()
        let before = document.materialize()
        let operations = try EditPlanner.planUngroup(
            groupID: "Pair", in: document, layout: WrapFixture.layout(of: document)
        )

        var inverses: [[EditOperation]] = []
        for operation in operations {
            try inverses.append(document.prepareInverse(of: operation))
            try document.apply(operation)
        }
        for inverse in inverses.reversed() {
            for operation in inverse {
                try document.apply(operation)
            }
        }
        #expect(document.materialize() == before)
    }
}
