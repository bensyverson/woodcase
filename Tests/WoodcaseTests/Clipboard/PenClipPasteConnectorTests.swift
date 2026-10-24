//
//  PenClipPasteConnectorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/plan(into:at:)`` attaches each carried connector to the pasted copies, at the
/// top level where Pen keeps connections, and never writes one with an end that names
/// nothing (Ben's ruling of 2026-10-23, Penumbra spec §11).
@MainActor
struct PenClipPasteConnectorTests {
    /// The insert of each connection a plan writes, by the inserted id.
    private func connectionInserts(_ plan: PastePlan) -> [String: EditOperation.InsertNode] {
        var found: [String: EditOperation.InsertNode] = [:]
        for insert in PasteFixture.inserts(plan) {
            if case .connection = insert.node.kind { found[insert.node.id] = insert }
        }
        return found
    }

    /// A hand-built clip: one rectangle, and a carried connector from it to `Elsewhere`,
    /// which the clip does not hold.
    private func strandedClip() throws -> PenClip {
        let json = """
        {"version": "2.20", "children": [
          {"type": "rectangle", "id": "R", "x": 0, "y": 0, "width": 10, "height": 10},
          {"type": "connection", "id": "K", "source": {"path": "R", "anchor": "right"},
           "target": {"path": "Elsewhere", "anchor": "left"}}
        ]}
        """
        return try PenClip(document: PenParser.parse(Data(json.utf8)), contentIDs: ["R"], connectorIDs: ["K"])
    }

    @Test("Pasting two connected cards attaches the carried connectors to the pasted copies")
    func attachesToCopies() throws {
        let document = try ConnectorFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB"], from: document)

        let plan = try clip.plan(into: document, at: .inPlace)
        try PasteFixture.apply(plan, to: document)

        try #require(plan.insertedConnectorIDs.count == 2)
        #expect(plan.droppedConnectorIDs.isEmpty)
        #expect(!plan.insertedRootIDs.contains { plan.insertedConnectorIDs.contains($0) })
        let newA = plan.insertedRootIDs[0], newB = plan.insertedRootIDs[1]
        let pastedTitle = try #require(document.childIDs(of: newA).first)
        let ab = try #require(document.node(id: plan.insertedConnectorIDs[0]))
        let tb = try #require(document.node(id: plan.insertedConnectorIDs[1]))
        #expect(ConnectorFixture.ends(of: ab) == [newA, newB])
        #expect(ConnectorFixture.ends(of: tb) == [pastedTitle, newB])
        #expect(document.node(id: "KAB") != nil, "the original stays")
    }

    @Test("Carried connectors land at the top level, after the copies, even in a container")
    func topLevel() throws {
        let document = try ConnectorFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB"], from: document)

        let plan = try clip.plan(into: document, at: .inside(containerID: "Board"))

        let inserts = connectionInserts(plan)
        #expect(inserts.count == 2)
        #expect(inserts.values.allSatisfy { $0.parentID == nil })
        let last = PasteFixture.inserts(plan).suffix(2).map(\.node.id)
        #expect(Set(last) == Set(plan.insertedConnectorIDs), "connectors go in after the nodes they name")
    }

    @Test("A connector that was copied itself lands at the top level too")
    func selectedTopLevel() throws {
        let document = try ConnectorFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB", "KAB"], from: document)

        let plan = try clip.plan(into: document, at: .inside(containerID: "Board"))
        try PasteFixture.apply(plan, to: document)

        try #require(plan.insertedRootIDs.count == 3)
        let pasted = try #require(plan.insertedRootIDs.last)
        #expect(document.parentID(of: pasted) == nil)
        #expect(ConnectorFixture.ends(of: document.node(id: pasted)) == Array(plan.insertedRootIDs.prefix(2)))
    }

    @Test("An end inside a pasted instance resolves in a target that had nothing")
    func instanceEndInEmptyTarget() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "Chip"], from: ConnectorFixture.document())
        let target = PasteFixture.empty()

        let plan = try clip.plan(into: target, at: .inPlace)
        try PasteFixture.apply(plan, to: target)

        let connector = try #require(plan.insertedConnectorIDs.first)
        let ends = try #require(ConnectorFixture.ends(of: target.node(id: connector)))
        #expect(ends.allSatisfy { ConnectorFixture.resolves($0, in: target) }, "\(ends)")
        #expect(ends[0].hasPrefix(plan.insertedRootIDs[1] + "/"))
    }

    @Test("A carried connector with an end the paste cannot resolve is left out, and named")
    func droppedCarried() throws {
        let target = PasteFixture.empty()

        let plan = try strandedClip().plan(into: target, at: .inPlace)

        #expect(connectionInserts(plan).isEmpty)
        #expect(plan.insertedConnectorIDs.isEmpty)
        #expect(plan.droppedConnectorIDs == ["K"])
    }

    @Test("A copied connector whose end is outside the copy attaches to the original in its own document")
    func selectedOutsideEndSameDocument() throws {
        let document = try ConnectorFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["CardA", "KAC"], from: document)

        let plan = try clip.plan(into: document, at: .inPlace)
        try PasteFixture.apply(plan, to: document)

        let pasted = try #require(plan.insertedRootIDs.last)
        #expect(ConnectorFixture.ends(of: document.node(id: pasted)) == [plan.insertedRootIDs[0], "CardC"])
        #expect(plan.droppedConnectorIDs.isEmpty)
    }

    @Test("A copied connector whose end names nothing in another document is left out")
    func selectedOutsideEndOtherDocument() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "KAC"], from: ConnectorFixture.document())
        let target = PasteFixture.empty()

        let plan = try clip.plan(into: target, at: .inPlace)
        try PasteFixture.apply(plan, to: target)

        #expect(plan.insertedRootIDs.count == 1)
        #expect(plan.droppedConnectorIDs == ["KAC"])
        #expect(connectionInserts(plan).isEmpty)
    }

    @Test("Cut and paste of two connected cards brings their connector back attached")
    func cutAndPaste() throws {
        let document = try ConnectorFixture.document()
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB"], from: document)
        let deletion = try EditPlanner.planDelete(nodeIDs: ["CardA", "CardB"], in: document)
        try WrapFixture.apply(deletion.operations, to: document)

        let plan = try clip.plan(into: document, at: .inPlace)
        try PasteFixture.apply(plan, to: document)

        #expect(plan.insertedConnectorIDs.count == 2)
        for id in plan.insertedConnectorIDs {
            let ends = try #require(ConnectorFixture.ends(of: document.node(id: id)))
            #expect(ends.allSatisfy { ConnectorFixture.resolves($0, in: document) }, "\(ends)")
        }
    }
}
