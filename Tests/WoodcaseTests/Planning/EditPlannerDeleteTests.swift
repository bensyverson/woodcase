//
//  EditPlannerDeleteTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Delete (``EditPlanner/planDelete(nodeIDs:in:)``): deleting a node also deletes every
/// connector attached to it or to anything inside it, in the same edit, so none is left
/// pointing at a node that no longer exists (Ben's ruling of 2026-10-23, Penumbra spec §11).
@MainActor
struct EditPlannerDeleteTests {
    /// `Board` holds `Card` (with `Title` and `Badge`), `Other`, `Lone` and `Pair`, a group
    /// of `G1` and `G2`; `Chip` is an instance of `Comp`, whose child is `Label`. The
    /// connectors, all at the top level as Pen keeps them:
    ///
    /// - `K1` `Title` → `Other`; `K2` `Other` → `Chip/Label`; `K3` `Card` → `Lone`;
    /// - `K4` `Lone` → `Other`; `K5` `Badge` → `Title`; `K6` `G1` → `Lone`.
    private static let json = """
    {
      "version": "2.20",
      "children": [
        { "type": "frame", "id": "Board", "x": 0, "y": 0, "width": 800, "height": 600, "layout": "none", "children": [
          { "type": "frame", "id": "Card", "x": 20, "y": 20, "width": 200, "height": 100, "layout": "none", "children": [
            { "type": "text", "id": "Title", "x": 10, "y": 10, "content": "Hi" },
            { "type": "rectangle", "id": "Badge", "x": 150, "y": 10, "width": 20, "height": 20 }
          ] },
          { "type": "rectangle", "id": "Other", "x": 400, "y": 20, "width": 40, "height": 40 },
          { "type": "rectangle", "id": "Lone", "x": 400, "y": 300, "width": 40, "height": 40 },
          { "type": "group", "id": "Pair", "x": 100, "y": 400, "children": [
            { "type": "rectangle", "id": "G1", "x": 0, "y": 0, "width": 20, "height": 20 },
            { "type": "rectangle", "id": "G2", "x": 40, "y": 0, "width": 20, "height": 20 }
          ] }
        ] },
        { "type": "frame", "id": "Comp", "reusable": true, "x": 0, "y": 700, "width": 100, "height": 40,
          "layout": "none", "children": [
          { "type": "text", "id": "Label", "x": 4, "y": 4, "content": "L" }
        ] },
        { "type": "ref", "id": "Chip", "ref": "Comp", "x": 600, "y": 0 },
        { "type": "connection", "id": "K1", "source": { "path": "Title", "anchor": "right" },
          "target": { "path": "Other", "anchor": "left" } },
        { "type": "connection", "id": "K2", "source": { "path": "Other", "anchor": "bottom" },
          "target": { "path": "Chip/Label", "anchor": "top" } },
        { "type": "connection", "id": "K3", "source": { "path": "Card", "anchor": "bottom" },
          "target": { "path": "Lone", "anchor": "left" } },
        { "type": "connection", "id": "K4", "source": { "path": "Lone", "anchor": "top" },
          "target": { "path": "Other", "anchor": "bottom" } },
        { "type": "connection", "id": "K5", "source": { "path": "Badge", "anchor": "left" },
          "target": { "path": "Title", "anchor": "right" } },
        { "type": "connection", "id": "K6", "source": { "path": "G1", "anchor": "top" },
          "target": { "path": "Lone", "anchor": "bottom" } }
      ]
    }
    """

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Data(Self.json.utf8)))
    }

    /// The ids a plan's operations delete, in order.
    private func deleted(_ plan: DeletionPlan) -> [String] {
        plan.operations.compactMap { operation in
            if case let .deleteNode(op) = operation { return op.nodeID }
            return nil
        }
    }

    /// The connectors still in the document, in document order.
    private func connectors(in document: EditableDocument) -> [String] {
        document.nodeIDsInDocumentOrder().filter { id in
            if case .connection = document.node(id: id)?.kind { return true }
            return false
        }
    }

    @Test("Deleting an endpoint deletes its connectors first, then the node")
    func endpoint() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["Other"], in: document)

        #expect(plan.nodeIDs == ["Other"])
        #expect(plan.connectorIDs == ["K1", "K2", "K4"])
        #expect(deleted(plan) == ["K1", "K2", "K4", "Other"])
        try WrapFixture.apply(plan.operations, to: document)
        #expect(connectors(in: document) == ["K3", "K5", "K6"])
    }

    @Test("Deleting a container deletes the connectors attached to it and to anything inside it, each once")
    func container() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["Card"], in: document)

        #expect(plan.connectorIDs == ["K1", "K3", "K5"], "K5 joins two nodes inside Card and goes once")
        #expect(deleted(plan) == ["K1", "K3", "K5", "Card"])
    }

    @Test("Deleting an instance deletes the connectors attached inside it")
    func instance() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["Chip"], in: document)

        #expect(plan.connectorIDs == ["K2"])
    }

    @Test("Deleting a node of a component deletes the connectors attached to it in every instance")
    func componentChild() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["Label"], in: document)

        #expect(plan.connectorIDs == ["K2"], "Chip/Label goes with Label")
    }

    @Test("Deleting both ends of a connector deletes it once")
    func bothEnds() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["Title", "Other"], in: document)

        #expect(plan.connectorIDs == ["K1", "K2", "K4", "K5"])
        #expect(deleted(plan) == ["K1", "K2", "K4", "K5", "Title", "Other"])
    }

    @Test("A connector deleted with its node is deleted once, as one of the nodes")
    func connectorInTheSelection() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["K1", "Other"], in: document)

        #expect(plan.nodeIDs == ["K1", "Other"])
        #expect(plan.connectorIDs == ["K2", "K4"])
        #expect(deleted(plan) == ["K2", "K4", "K1", "Other"])
        try WrapFixture.apply(plan.operations, to: document)
    }

    @Test("A node inside another deleted node is not deleted again")
    func nestedSelection() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["Title", "Card", "Card"], in: document)

        #expect(plan.nodeIDs == ["Card"])
        #expect(deleted(plan) == ["K1", "K3", "K5", "Card"])
        try WrapFixture.apply(plan.operations, to: document)
    }

    @Test("Deleting a node no connector touches deletes only the node")
    func unattached() throws {
        let document = try document()
        let plan = try EditPlanner.planDelete(nodeIDs: ["G2"], in: document)

        #expect(plan.connectorIDs.isEmpty)
        #expect(deleted(plan) == ["G2"])
    }

    @Test("A node inside an instance, or no node at all, is refused")
    func refusals() throws {
        let document = try document()
        #expect(throws: EditRefusal.self) { try EditPlanner.planDelete(nodeIDs: ["Chip/Label"], in: document) }
        #expect(throws: EditRefusal.self) { try EditPlanner.planDelete(nodeIDs: ["Ghost"], in: document) }
    }

    @Test("Undo restores the node and its connectors together, where they were")
    func undo() throws {
        let original = try document()
        let session = try DocumentSession(
            document: PenParser.parse(Data(Self.json.utf8)), author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
        )
        let plan = try EditPlanner.planDelete(nodeIDs: ["Card", "Other"], in: session.document)

        try session.submit(.local(LocalEdit(operations: plan.operations)))
        #expect(session.document.node(id: "Card") == nil)
        #expect(connectors(in: session.document) == ["K6"])

        try session.submit(.undo)
        #expect(session.document.rootOrder == original.rootOrder)
        #expect(session.document.nodeIDsInDocumentOrder() == original.nodeIDsInDocumentOrder())
        for id in original.nodeIDsInDocumentOrder() {
            #expect(session.document.node(id: id) == original.node(id: id), "\(id) came back changed")
        }
    }

    @Test("Ungroup leaves connectors alone: the children it frees keep theirs")
    func ungroup() throws {
        let document = try document()
        let operations = try EditPlanner.planUngroup(
            groupID: "Pair", in: document, layout: WrapFixture.layout(of: document)
        )

        try WrapFixture.apply(operations, to: document)
        #expect(connectors(in: document) == ["K1", "K2", "K3", "K4", "K5", "K6"])
    }

    @Test("A batch rm takes the connectors along and says which")
    func batchRemove() throws {
        let document = try document()
        let card = try #require(NodeAddress("Board/Card"))

        let result = try BatchApplier.applyOne(.rm(BatchOperation.RemoveOp(target: card)), to: document)

        #expect(connectors(in: document) == ["K2", "K4", "K6"])
        let divergence = try #require(result.divergences.first { $0.kind == .deletedConnectors })
        #expect(divergence.severity == .note)
        #expect(divergence.note == "removing Card also removed 3 connectors that ended on it or inside it: #K1, #K3, #K5")
    }

    @Test("A batch replace that drops a node takes its connectors along")
    func batchReplace() throws {
        let document = try document()
        let card = try #require(NodeAddress("Board/Card"))
        let replacement = try PenSubtreeDecoder.node(from: [
            "type": "frame", "name": "Card", "x": 20, "y": 20, "width": 200, "height": 100, "layout": "none",
            "children": [["type": "rectangle", "id": "Badge", "name": "Badge", "x": 0, "y": 0, "width": 20, "height": 20]],
        ])

        let result = try BatchApplier.applyOne(
            .replace(BatchOperation.ReplaceOp(target: card, node: replacement)), to: document
        )

        #expect(document.node(id: "Title") == nil)
        #expect(connectors(in: document) == ["K2", "K3", "K4", "K6"], "K1 and K5 named Title")
        #expect(result.divergences.contains { $0.kind == .deletedConnectors })
    }
}
