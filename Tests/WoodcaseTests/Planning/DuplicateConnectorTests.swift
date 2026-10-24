//
//  DuplicateConnectorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``EditPlanner/planDuplicate(nodeIDs:in:)`` carries every connector whose two ends are
/// both inside the duplicated nodes, its ends on the copies, in the same plan; one with an
/// end outside stays single (Ben's ruling of 2026-10-23, Penumbra spec §11).
@MainActor
struct DuplicateConnectorTests {
    /// The connections a plan inserts, in order.
    private func connectionInserts(_ operations: [EditOperation]) -> [PenNode] {
        operations.compactMap { operation in
            guard case let .insertNode(insert) = operation, case .connection = insert.node.kind else { return nil }
            return insert.node
        }
    }

    @Test("Duplicating two connected nodes copies their connectors onto the copies; one end outside stays single")
    func storedPair() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["CardA", "CardB"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let newA = plan.placedIDs[0], newB = plan.placedIDs[1]
        let newTitle = try #require(doc.childIDs(of: newA).first)
        let copies = connectionInserts(plan.operations)
        #expect(copies.count == 2, "KAB and KTB, not KAC (CardC is outside) nor KChip")
        #expect(plan.carriedConnectorIDs == copies.map(\.id))
        #expect(copies.map { ConnectorFixture.ends(of: $0) } == [[newA, newB], [newTitle, newB]])
        #expect(copies.allSatisfy { !["KAB", "KTB"].contains($0.id) }, "the copies take fresh ids")
        #expect(ConnectorFixture.ends(of: doc.node(id: "KAB")) == ["CardA", "CardB"], "the original stays")
        #expect(!plan.placedIDs.contains { plan.carriedConnectorIDs.contains($0) }, "the copies are not placed nodes")
    }

    @Test("A carried connector keeps everything but its id and its ends")
    func keepsStyle() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["CardA", "CardB"], in: doc)

        let copy = try #require(connectionInserts(plan.operations).first)
        let original = try #require(doc.node(id: "KAB"))
        #expect(copy.common == original.common)
        #expect(copy.extras == original.extras)
        guard case let .connection(copied) = copy.kind, case let .connection(source) = original.kind else {
            Issue.record("not connections")
            return
        }
        #expect(copied.source.anchor == source.source.anchor && copied.target.anchor == source.target.anchor)
    }

    @Test("A connector carried with copies lands at the top level, after them")
    func topLevelAfterTheCopies() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["CardA", "CardB"], in: doc)

        let inserts = plan.operations.compactMap { operation -> EditOperation.InsertNode? in
            guard case let .insertNode(insert) = operation else { return nil }
            return insert
        }
        #expect(inserts.suffix(2).allSatisfy { $0.parentID == nil && $0.index == nil })
        #expect(Set(inserts.suffix(2).map(\.node.id)) == Set(plan.carriedConnectorIDs))
    }

    @Test("Duplicating a container carries the connectors between the nodes inside it")
    func insideAContainer() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["Board"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let board = plan.placedIDs[0]
        let children = doc.childIDs(of: board)
        let newA = children[0], newB = children[1], newC = children[2], newChip = children[3]
        let newTitle = try #require(doc.childIDs(of: newA).first)
        let ends = connectionInserts(plan.operations).map { ConnectorFixture.ends(of: $0) }
        #expect(ends == [[newA, newB], [newTitle, newB], [newA, newC], ["\(newChip)/Label", newA]])
    }

    @Test("An end inside a copied instance follows the instance's copy")
    func intoAnInstance() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["CardA", "Chip"], in: doc)

        let newA = plan.placedIDs[0]
        let newChip = try #require(plan.placedIDs[1].split(separator: "/").first.map(String.init))
        let ends = connectionInserts(plan.operations).map { ConnectorFixture.ends(of: $0) }
        #expect(ends == [["\(newChip)/Label", newA]])
    }

    @Test("A duplicated connector whose ends are both copied follows the copies")
    func selectedConnector() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["CardA", "CardB", "KAB"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let newA = plan.placedIDs[0], newB = plan.placedIDs[1], newK = plan.placedIDs[2]
        #expect(ConnectorFixture.ends(of: doc.node(id: newK)) == [newA, newB])
        #expect(connectionInserts(plan.operations).count == 2, "KAB's copy once, and KTB carried")
    }

    @Test("A duplicated connector alone keeps its ends")
    func connectorAlone() throws {
        let doc = try ConnectorFixture.document()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["KAB"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        #expect(ConnectorFixture.ends(of: doc.node(id: plan.placedIDs[0])) == ["CardA", "CardB"])
        #expect(plan.carriedConnectorIDs.isEmpty)
    }

    // MARK: - Slot content

    /// The slot fixture with connectors: `KR` between two rows of `Filled`'s fill, `KD`
    /// inside the default content's instance, and `KOut` from a row to `Loose`.
    private func slotDocument() throws -> EditableDocument {
        let doc = try SlotScreenFixture.document()
        let connectors = try PenParser.parse(Data("""
        {"version": "2.19", "children": [
          {"type": "connection", "id": "KR", "source": {"path": "Filled/Row1", "anchor": "right"},
           "target": {"path": "Filled/Row3", "anchor": "left"}},
          {"type": "connection", "id": "KD", "source": {"path": "Default/Empty1", "anchor": "right"},
           "target": {"path": "Default/Empty1/ETxt", "anchor": "left"}},
          {"type": "connection", "id": "KOut", "source": {"path": "Filled/Row1", "anchor": "right"},
           "target": {"path": "Loose", "anchor": "left"}}
        ]}
        """.utf8)).children
        for connector in connectors {
            try doc.apply(.insertNode(EditOperation.InsertNode(node: connector)))
        }
        return doc
    }

    /// The ref path an instance in a fill answers to: its expanded id without the
    /// component root.
    private func refPath(_ expandedID: String) -> String {
        expandedID.split(separator: "/").dropLast().joined(separator: "/")
    }

    @Test("An instance in a fill encloses an end that names it by its ref's path")
    func enclosedInstanceInFill() throws {
        let doc = try slotDocument()

        let carried = EditPlanner.connectorIDs(enclosedBy: ["Filled/Row1/ItemA", "Filled/Row3/ItemA"], in: doc)

        #expect(carried == ["KR"])
    }

    @Test("Duplicating connected slot content carries the connector, ends on the copies in the fill")
    func slotPair() throws {
        let doc = try slotDocument()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["Filled/Row1/ItemA", "Filled/Row3/ItemA"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let copies = connectionInserts(plan.operations)
        #expect(copies.count == 1, "KR, not KOut")
        #expect(copies.map { ConnectorFixture.ends(of: $0) } == [plan.placedIDs.map(refPath)])
        #expect(ConnectorFixture.ends(of: doc.node(id: "KR")) == ["Filled/Row1", "Filled/Row3"])
    }

    @Test("Duplicating default content carries its connector onto the copy, and the original onto the fill")
    func slotDefault() throws {
        let doc = try slotDocument()

        let plan = try EditPlanner.planDuplicate(nodeIDs: ["Default/Empty1/EmptyState"], in: doc)
        try SlotScreenFixture.apply(plan.operations, to: doc)

        let original = refPath(plan.renamed("Default/Empty1/EmptyState"))
        let copy = refPath(plan.placedIDs[0])
        #expect(original != "Default/Empty1")
        #expect(ConnectorFixture.ends(of: doc.node(id: "KD")) == [original, original + "/ETxt"])
        let copies = connectionInserts(plan.operations)
        #expect(copies.map { ConnectorFixture.ends(of: $0) } == [[copy, copy + "/ETxt"]])
    }
}
