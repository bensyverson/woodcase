//
//  BatchApplierOperationTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct BatchApplierOperationTests {
    // MARK: - Helpers

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func apply(_ jsonl: String, to document: EditableDocument) throws -> BatchReport {
        try BatchApplier.apply(BatchOperation.decodeJSONL(jsonl), to: document)
    }

    // MARK: - Move and remove

    @Test("An mv relocates a node without copying it")
    func moveRelocates() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"mv","target":"Canvas/Cards/First","parent":"Board","at":0}"#, to: doc)

        #expect(report.lines[0].status == .applied)
        #expect(doc.parentID(of: "Cd101") == "Brd01")
        #expect(doc.childIDs(of: "Brd01") == ["Cd101", "Chi01"])
        #expect(doc.childIDs(of: "Crd01") == ["Cd201"])
    }

    @Test("An mv with no parent moves the node to the document root")
    func moveToRoot() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"mv","target":"Canvas/Cards/First"}"#, to: doc)

        #expect(report.lines[0].status == .applied)
        #expect(doc.parentID(of: "Cd101") == nil)
        #expect(doc.rootOrder.contains("Cd101"))
    }

    @Test("An rm deletes the node and its descendants")
    func removeDeletesSubtree() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"rm","target":"Canvas/Cards"}"#, to: doc)

        #expect(report.lines[0].status == .applied)
        #expect(doc.node(id: "Crd01") == nil)
        #expect(doc.node(id: "Cd101") == nil)
    }

    @Test("An rm with detach detaches each instance before deleting the component")
    func removeWithDetach() throws {
        let doc = try makeDocument()
        let report = try apply(#"{"op":"rm","target":"Component","detach":true}"#, to: doc)

        #expect(report.lines[0].status == .applied)
        #expect(doc.node(id: "Cmp01") == nil)
        #expect(doc.node(id: "Chi01") == nil)
        // The instance survives as independent nodes under its old parent.
        let survivors = doc.childIDs(of: "Brd01")
        #expect(survivors.count == 1)
        // Expansion carries the ref node's own name onto the detached root.
        let survivorID = try #require(survivors.first)
        let detached = try #require(doc.node(id: survivorID))
        #expect(detached.common.name == "Chip")
        if case .ref = detached.kind {
            Issue.record("the detached instance is still a ref")
        }
    }

    // MARK: - Override

    @Test("An override writes into the instance's descendants map, keyed as Pen keys it")
    func overrideWritesDescendant() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"override","target":"Board/Chip/Label","props":{"content":"Menu"}}
        """#, to: doc)

        #expect(report.lines[0].status == .applied)
        guard case let .ref(data) = try #require(doc.node(id: "Chi01")).kind else {
            Issue.record("expected Chi01 to be a ref")
            return
        }
        #expect(data.descendants?["Lbl01"]?.properties["content"] == .string("Menu"))
    }

    @Test("A set addressed inside an instance fails, pointing at override")
    func setInsideInstanceFails() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"set","target":"Board/Chip/Label","props":{"kind.content":"Menu"}}
        """#, to: doc)

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("Board/Chip/Label"))
        #expect(message.contains("override"))
    }

    @Test("An override addressed at a plain node fails, saying it is not inside an instance")
    func overrideOnPlainNodeFails() throws {
        let doc = try makeDocument()
        let report = try apply(#"""
        {"op":"override","target":"Canvas/Title","props":{"content":"Menu"}}
        """#, to: doc)

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("Canvas/Title"))
        #expect(message.contains("instance"))
    }

    // MARK: - Document ops

    @Test("A var op adds a variable and then updates it")
    func variableAddThenUpdate() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"var","name":"brand","value":{"type":"color","value":"#ff0000"}}
        {"op":"var","name":"brand","value":{"type":"color","value":"#00ff00"}}
        """, to: doc)

        #expect(report.lines.map(\.status) == [.applied, .applied])
        guard case let .simple(value) = try #require(doc.variables?["brand"]).value else {
            Issue.record("expected a simple variable value")
            return
        }
        #expect(value == .string("#00ff00"))
    }

    @Test("A theme-axis op adds an axis and then replaces its options")
    func themeAxisAddThenUpdate() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"theme-axis","name":"mode","options":["light","dark"]}
        {"op":"theme-axis","name":"mode","options":["light","dark","hc"]}
        """, to: doc)

        #expect(report.lines.map(\.status) == [.applied, .applied])
        #expect(doc.themes?["mode"] == ["light", "dark", "hc"])
    }

    // MARK: - Tags

    @Test("A later op addresses a node an earlier op created, by tag")
    func tagsResolveForwardReferences() throws {
        let doc = try makeDocument()
        let report = try apply("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10},"tag":"hero"}
        {"op":"add","parent":"@hero","node":{"type":"text","name":"Caption","content":"hi"},"tag":"cap"}
        {"op":"set","target":"@cap","props":{"kind.content":"there"}}
        """, to: doc)

        #expect(report.lines.map(\.status) == [.applied, .applied, .applied])
        let heroID = try #require(report.lines[0].created.first?.id)
        let capID = try #require(report.lines[1].created.first?.id)
        #expect(doc.parentID(of: capID) == heroID)
        guard case let .text(data) = try #require(doc.node(id: capID)).kind else {
            Issue.record("expected a text node")
            return
        }
        #expect(data.content?.literalValue == "there")
    }
}
