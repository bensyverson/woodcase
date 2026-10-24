//
//  SlotConnectorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A connector attached to a slot's default content follows it when the first structural
/// change copies that content into a fill with fresh ids (Penumbra spec §13.5 rule 6).
@MainActor
struct SlotConnectorTests {
    /// The fixture with `K1` from `Default/Empty1` (an instance in the default content)
    /// and `K2` from `Default/Empty1/ETxt` (a node inside it), both to `Loose`.
    private func document() throws -> EditableDocument {
        let doc = try SlotScreenFixture.document()
        let connectors = try PenParser.parse(Data("""
        {"version": "2.19", "children": [
          {"type": "connection", "id": "K1", "source": {"path": "Default/Empty1", "anchor": "right"},
           "target": {"path": "Loose", "anchor": "left"}},
          {"type": "connection", "id": "K2", "source": {"path": "Default/Empty1/ETxt", "anchor": "right"},
           "target": {"path": "Loose", "anchor": "left"}}
        ]}
        """.utf8)).children
        for connector in connectors {
            try doc.apply(.insertNode(EditOperation.InsertNode(node: connector)))
        }
        return doc
    }

    private func source(of id: String, in doc: EditableDocument) -> String? {
        guard case let .connection(data)? = doc.node(id: id)?.kind else { return nil }
        return data.source.path
    }

    @Test("Copying default content into a fill rewrites the connector ends that named it, in the same plan")
    func endsFollowTheCopy() throws {
        let doc = try document()
        let rectangle = PenNode(
            id: "NewR", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(width: .fixed(10), height: .fixed(10)))
        )

        let plan = try EditPlanner.planInsert([rectangle], into: "Default/List", in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let copy = plan.renamed("Default/Empty1")
        #expect(copy != "Default/Empty1")
        #expect(source(of: "K1", in: doc) == copy)
        #expect(source(of: "K2", in: doc) == copy + "/ETxt")
    }

    @Test("A connector to default content is deleted with it, not rewritten")
    func deletedContentTakesItsConnectors() throws {
        let doc = try document()

        let plan = try EditPlanner.planDelete(nodeIDs: ["Default/Empty1/EmptyState"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(Set(plan.connectorIDs) == ["K1", "K2"])
        #expect(doc.node(id: "K1") == nil)
    }
}
