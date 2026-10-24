//
//  BatchCopyConnectorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A `cp` line carries every connector whose two ends are both inside the copied node, its
/// ends on the copy; one with an end outside stays single (Ben's ruling of 2026-10-23,
/// Penumbra spec §11, through ``EditPlanner/connectorIDs(enclosedBy:in:)``).
@MainActor
struct BatchCopyConnectorTests {
    private func apply(_ jsonl: String, to document: EditableDocument) throws -> BatchReport {
        try BatchApplier.apply(BatchOperation.decodeJSONL(jsonl), to: document)
    }

    /// The ends of every connection the document holds that `before` did not.
    private func newConnections(in document: EditableDocument, before: Set<String>) -> [[String]] {
        document.nodeIDsInDocumentOrder().filter { !before.contains($0) }.compactMap { id in
            ConnectorFixture.ends(of: document.node(id: id))
        }
    }

    @Test("Copying a container carries the connectors between the nodes inside it, onto the copies")
    func deepCopy() throws {
        let doc = try ConnectorFixture.document()
        let before = Set(doc.nodeIDsInDocumentOrder())

        let report = try apply(#"{"op":"cp","source":"Board"}"#, to: doc)

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let board = try #require(report.lines[0].created.first?.id)
        let children = doc.childIDs(of: board)
        let newA = children[0], newB = children[1], newC = children[2], newChip = children[3]
        let newTitle = try #require(doc.childIDs(of: newA).first)
        #expect(newConnections(in: doc, before: before) == [
            [newA, newB], [newTitle, newB], [newA, newC], ["\(newChip)/Label", newA],
        ])
        #expect(ConnectorFixture.ends(of: doc.node(id: "KAB")) == ["CardA", "CardB"], "the original stays")
    }

    @Test("A connector with an end outside the copied node stays single")
    func endOutside() throws {
        let doc = try ConnectorFixture.document()
        let before = Set(doc.nodeIDsInDocumentOrder())

        let report = try apply(#"{"op":"cp","source":"CardA","parent":"Board"}"#, to: doc)

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        #expect(newConnections(in: doc, before: before).isEmpty)
    }

    @Test("Placing a component carries a connector inside it onto the instance")
    func instance() throws {
        let doc = try ConnectorFixture.document()
        let inner = try PenParser.parse(Data("""
        {"version": "2.20", "children": [
          {"type": "connection", "id": "KComp", "source": {"path": "Comp", "anchor": "top"},
           "target": {"path": "Label", "anchor": "bottom"}}
        ]}
        """.utf8)).children[0]
        try doc.apply(.insertNode(EditOperation.InsertNode(node: inner)))
        let before = Set(doc.nodeIDsInDocumentOrder())

        let report = try apply(#"{"op":"cp","source":"Comp","parent":"Board"}"#, to: doc)

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let instance = try #require(report.lines[0].created.first?.id)
        #expect(newConnections(in: doc, before: before) == [[instance, "\(instance)/Label"]])
    }

    @Test("Every copy of an each line carries its own connectors")
    func eachRow() throws {
        let doc = try ConnectorFixture.document()
        let before = Set(doc.nodeIDsInDocumentOrder())

        let report = try apply(
            #"{"op":"cp","source":"Board","each":[{"common.name":"B1"},{"common.name":"B2"}]}"#, to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        #expect(report.lines[0].created.count == 2)
        #expect(newConnections(in: doc, before: before).count == 8)
    }

    @Test("A copy that carries connectors says which, as a note")
    func note() throws {
        let doc = try ConnectorFixture.document()

        let card = try apply(#"{"op":"cp","source":"CardA","parent":"Board"}"#, to: doc)
        #expect(!card.lines[0].divergences.contains { $0.kind == .carriedConnectors }, "KTB ends outside CardA")

        let board = try apply(#"{"op":"cp","source":"Board"}"#, to: doc)
        let divergence = try #require(board.lines[0].divergences.first { $0.kind == .carriedConnectors })
        #expect(divergence.severity == .note)
        #expect(divergence.note.hasPrefix("copying Board also copied 4 connectors between nodes inside it: "))
    }
}
