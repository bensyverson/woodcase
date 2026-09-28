//
//  BatchApplierTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct BatchApplierTests {
    // MARK: - Helpers

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/batch.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    private func ops(_ jsonl: String) throws -> [BatchOperation] {
        try BatchOperation.decodeJSONL(jsonl)
    }

    /// The literal `content` of a text node, or `nil` if it is not text.
    private func text(_ nodeID: String, in document: EditableDocument) -> String? {
        guard case let .text(data) = document.node(id: nodeID)?.kind else { return nil }
        return data.content?.literalValue
    }

    // MARK: - Partial application

    @Test("A bad op in the middle does not stop the independent ops before and after it")
    func badOpInTheMiddle() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.nonsense":1}}
        {"op":"set","target":"Canvas/Cards/Second","props":{"common.name":"After"}}
        """)
        let report = BatchApplier.apply(batch, to: doc)

        #expect(report.lines.map(\.status) == [.applied, .failed, .applied])
        #expect(text("Ttl01", in: doc) == "Before")
        #expect(doc.node(id: "Cd201")?.common.name == "After")
        #expect(doc.node(id: "Cd101")?.common.name == "First")
    }

    @Test("A failed line's message names the property and the node's type")
    func failureMessageTeaches() throws {
        let doc = try makeDocument()
        let report = try BatchApplier.apply(ops("""
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.nonsense":1}}
        """), to: doc)

        let message = try #require(report.lines[0].error)
        #expect(message.contains("kind.nonsense"))
        #expect(message.contains("frame"))
        #expect(report.lines[0].isRevisionConflict == false)
    }

    @Test("An address that matches nothing fails that line, never silently doing nothing")
    func addressNotFound() throws {
        let doc = try makeDocument()
        let report = try BatchApplier.apply(ops("""
        {"op":"set","target":"Canvas/Nowhere","props":{"common.name":"x"}}
        """), to: doc)

        #expect(report.lines[0].status == .failed)
        #expect(try #require(report.lines[0].error).contains("Canvas/Nowhere"))
    }

    // MARK: - Cascade

    @Test("An op referencing a failed op's tag is cascaded, not failed")
    func cascadeByTag() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","width":10},"tag":"hero"}
        {"op":"set","target":"@hero","props":{"common.name":"Hero"}}
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Independent"}}
        """)
        let report = BatchApplier.apply(batch, to: doc)

        #expect(report.lines.map(\.status) == [.failed, .cascaded, .applied])
        #expect(report.lines[1].error != nil)
    }

    @Test("An op addressing a node a failed op would have created is cascaded, and its siblings are not")
    func cascadeByAddress() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Third","width":10},"at":99}
        {"op":"add","parent":"Canvas/Cards/Third","node":{"type":"frame","name":"Deep","width":5}}
        {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Untouched"}}
        """)
        let report = BatchApplier.apply(batch, to: doc)

        #expect(report.lines.map(\.status) == [.failed, .cascaded, .applied])
        #expect(doc.node(id: "Cd101")?.common.name == "Untouched")
    }

    @Test("A cascade propagates through a chain of tags")
    func cascadeChain() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","width":10},"tag":"one"}
        {"op":"cp","source":"@one","parent":"Canvas/Cards","tag":"two"}
        {"op":"set","target":"@two","props":{"common.name":"Two"}}
        """)
        let report = BatchApplier.apply(batch, to: doc)

        #expect(report.lines.map(\.status) == [.failed, .cascaded, .cascaded])
    }

    @Test("A later op on the same target as a failed op is cascaded, not failed")
    func cascadeBySharedTarget() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.nonsense":1}}
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Later"}}
        """)
        let report = BatchApplier.apply(batch, to: doc)

        #expect(report.lines.map(\.status) == [.failed, .cascaded])
        #expect(text("Ttl01", in: doc) == "Canvas")
    }

    // MARK: - Atomic

    @Test("Atomic mode leaves the document completely unchanged after any failure")
    func atomicDiscardsEverything() throws {
        let doc = try makeDocument()
        let before = doc.documentRevision
        let batch = try ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10}}
        {"op":"set","target":"Canvas/Cards/First","props":{"kind.nonsense":1}}
        """)
        let report = BatchApplier.apply(batch, to: doc, atomic: true)

        #expect(doc.documentRevision == before)
        #expect(text("Ttl01", in: doc) == "Canvas")
        #expect(report.lines[2].status == .failed)
        #expect(report.succeeded == false)
    }

    @Test("Atomic mode applies everything when every line succeeds")
    func atomicAppliesOnFullSuccess() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Before"}}
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10},"tag":"hero"}
        {"op":"set","target":"@hero","props":{"kind.width":20}}
        """)
        let report = BatchApplier.apply(batch, to: doc, atomic: true)

        #expect(report.succeeded)
        #expect(text("Ttl01", in: doc) == "Before")
        let heroID = try #require(report.lines[1].created.first?.id)
        #expect(doc.node(id: heroID)?.common.name == "Hero")
    }

    @Test("The ids an atomic batch reports are the ids the real document ends up with")
    func atomicReportsTheRealIDs() throws {
        let doc = try makeDocument()
        let report = try BatchApplier.apply(ops("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10,\
        "children":[{"type":"text","name":"Caption","content":"hi"}]}}
        """), to: doc, atomic: true)

        let created = try #require(report.lines[0].created.first)
        #expect(doc.node(id: created.id) != nil)
        let childID = try #require(created.children.first?.id)
        #expect(doc.node(id: childID) != nil)
        #expect(doc.parentID(of: childID) == created.id)
    }
}
