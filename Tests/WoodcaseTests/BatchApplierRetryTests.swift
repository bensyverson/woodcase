//
//  BatchApplierRetryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct BatchApplierRetryTests {
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

    /// The declared `width` of a frame node, or `nil` if it is not a frame.
    private func frameWidth(_ nodeID: String, in document: EditableDocument) -> PenSizing? {
        guard case let .frame(data) = document.node(id: nodeID)?.kind else { return nil }
        return data.width
    }

    // MARK: - Retry

    @Test("Retry re-applies exactly the failed and cascaded lines")
    func retryReRunsOnlyWhatFailed() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"First pass"}}
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","width":10},"tag":"hero"}
        {"op":"set","target":"@hero","props":{"common.name":"Hero"}}
        """)
        let first = BatchApplier.apply(batch, to: doc)
        #expect(first.lines.map(\.status) == [.applied, .failed, .cascaded])
        #expect(first.retryableLines == [1, 2])

        // Fix the unnamed node and retry.
        var fixed = batch
        guard case var .add(add) = fixed[1] else {
            Issue.record("expected an add op")
            return
        }
        add.node.common.name = "Hero"
        fixed[1] = .add(add)

        // A line that already applied must not run twice.
        try doc.apply(.setProperties(EditOperation.SetProperties(
            nodeID: "Ttl01", properties: ["kind.content": .string("edited between runs")]
        )))

        let second = BatchApplier.retry(fixed, report: first, to: doc)
        #expect(second.lines.count == 3)
        #expect(second.lines.map(\.status) == [.applied, .applied, .applied])
        #expect(text("Ttl01", in: doc) == "edited between runs")

        let heroID = try #require(second.lines[1].created.first?.id)
        #expect(doc.node(id: heroID)?.common.name == "Hero")
    }

    @Test("Retry resolves a tag created by a line that already applied")
    func retrySeesEarlierTags() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10},"tag":"hero"}
        {"op":"set","target":"@hero","props":{"kind.nonsense":1}}
        """)
        let first = BatchApplier.apply(batch, to: doc)
        #expect(first.lines.map(\.status) == [.applied, .failed])

        var fixed = batch
        guard case var .set(set) = fixed[1] else {
            Issue.record("expected a set op")
            return
        }
        set.props = ["kind.width": .int(42)]
        fixed[1] = .set(set)

        let second = BatchApplier.retry(fixed, report: first, to: doc)
        #expect(second.lines.map(\.status) == [.applied, .applied])
        let heroID = try #require(first.lines[0].created.first?.id)
        #expect(frameWidth(heroID, in: doc) == .fixed(42))
    }

    @Test("Retry on a report with nothing to retry changes nothing")
    func retryNoop() throws {
        let doc = try makeDocument()
        let batch = try ops(#"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Once"}}"#)
        let first = BatchApplier.apply(batch, to: doc)
        let before = doc.documentRevision

        let second = BatchApplier.retry(batch, report: first, to: doc)
        #expect(second.lines.map(\.status) == [.applied])
        #expect(doc.documentRevision == before)
    }

    // MARK: - Revisions

    @Test("A stale rev fails that line with a conflict message naming both revisions")
    func staleRevision() throws {
        let doc = try makeDocument()
        let stale = "0000000000000000"
        let report = try BatchApplier.apply(ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Nope"},"rev":"\(stale)"}
        {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Fine"}}
        """), to: doc)

        #expect(report.lines.map(\.status) == [.failed, .applied])
        let message = try #require(report.lines[0].error)
        #expect(message.contains(stale))
        #expect(try message.contains(#require(doc.revision(of: "Ttl01"))))
        #expect(text("Ttl01", in: doc) == "Canvas")
        #expect(report.lines[0].isRevisionConflict == true)
        #expect(report.lines[1].isRevisionConflict == false)
    }

    @Test("A current rev lets the line through")
    func matchingRevision() throws {
        let doc = try makeDocument()
        let rev = try #require(doc.revision(of: "Ttl01"))
        let report = try BatchApplier.apply(ops("""
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"Fresh"},"rev":"\(rev)"}
        """), to: doc)

        #expect(report.lines[0].status == .applied)
        #expect(text("Ttl01", in: doc) == "Fresh")
    }

    @Test("A root-level add checks its rev against the whole document")
    func rootLevelRevisionGuardsTheDocument() throws {
        let doc = try makeDocument()
        let report = try BatchApplier.apply(ops("""
        {"op":"add","node":{"type":"frame","name":"Loose","width":10},"rev":"0000000000000000"}
        """), to: doc)

        #expect(report.lines[0].status == .failed)
        #expect(try #require(report.lines[0].error).contains(doc.documentRevision))
        #expect(report.lines[0].isRevisionConflict == true)
    }

    // MARK: - Report

    @Test("The report carries the identity it was applied under and the resulting revision")
    func reportMetadata() throws {
        let doc = try makeDocument()
        let identity = PeerID(rawValue: "ben")
        let report = try BatchApplier.apply(
            ops(#"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Hi"}}"#),
            to: doc, identity: identity
        )

        #expect(report.identity == identity)
        #expect(report.documentRevision == doc.documentRevision)
        #expect(report.succeeded)
    }

    @Test("An applied line carries the inverse that undoes it")
    func appliedLineCarriesItsInverse() throws {
        let doc = try makeDocument()
        let report = try BatchApplier.apply(
            ops(#"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Changed"}}"#),
            to: doc
        )

        #expect(text("Ttl01", in: doc) == "Changed")
        for operation in report.lines[0].inverse {
            try doc.apply(operation)
        }
        #expect(text("Ttl01", in: doc) == "Canvas")
    }

    @Test("A report survives a JSON round trip, so a retry can read one written to disk")
    func reportRoundTrips() throws {
        let doc = try makeDocument()
        let batch = try ops("""
        {"op":"add","parent":"Canvas/Cards","node":{"type":"frame","name":"Hero","width":10},"tag":"hero"}
        {"op":"set","target":"Canvas/Title","props":{"kind.nonsense":1}}
        {"op":"mv","target":"Canvas/Cards/First","parent":"Board"}
        """)
        let report = BatchApplier.apply(batch, to: doc, identity: PeerID(rawValue: "ben"))
        #expect(report.lines.map(\.status) == [.applied, .failed, .applied])

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BatchReport.self, from: data)
        #expect(decoded == report)
        #expect(decoded.retryableLines == [1])
    }

    @Test("A failed line carries no inverse")
    func failedLineHasNoInverse() throws {
        let doc = try makeDocument()
        let report = try BatchApplier.apply(
            ops(#"{"op":"set","target":"Canvas/Title","props":{"kind.nonsense":1}}"#),
            to: doc
        )
        #expect(report.lines[0].inverse.isEmpty)
    }
}
