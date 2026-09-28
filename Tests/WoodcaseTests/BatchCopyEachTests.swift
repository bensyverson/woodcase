//
//  BatchCopyEachTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The `cp` op's `each` array and its path-keyed `props` — the batch half of what the
/// `cp` verb has always taken on argv.
///
/// One assignment path serves both: the op splits `"Label/kind.content"` into the copy's
/// root and the node inside it, and `each` is the loop the verb spells `--each`. A batch
/// that places twelve dressed instances is twelve rows on one line, not twelve lines and
/// a read in between.
@MainActor
struct BatchCopyEachTests {
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

    /// The overrides an instance carries, keyed as Pen keys them.
    private func overrides(of instance: PenNode?) -> [String: PenDescendantOverride] {
        guard let instance, case let .ref(data) = instance.kind else { return [:] }
        return data.descendants ?? [:]
    }

    // MARK: - Path-keyed props

    @Test("A path-keyed prop on a cp op becomes an override inside the instance")
    func pathKeyedPropBecomesAnOverride() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Component","parent":"Canvas",\
            "props":{"common.name":"Chip","Label/kind.content":"Hello"}}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let created = try #require(report.lines[0].created.first)
        #expect(overrides(of: doc.node(id: created.id))["Lbl01"]?
            .properties["content"] == .string("Hello"))
        #expect(doc.node(id: created.id)?.common.name == "Chip")
    }

    @Test("A path-keyed prop on a deep copy sets the node inside the copy, not the source")
    func pathKeyedPropSetsInsideTheCopy() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Canvas","parent":"Board",\
            "props":{"common.name":"Canvas2","Title/kind.content":"Deep"}}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let created = try #require(report.lines[0].created.first)
        let title = try #require(created.children.first { $0.name == "Title" })
        guard case let .text(data) = doc.node(id: title.id)?.kind else {
            Issue.record("the copied Title is not text")
            return
        }
        #expect(data.content?.literalValue == "Deep")
        guard case let .text(source) = doc.node(id: "Ttl01")?.kind else {
            Issue.record("the source Title is not text")
            return
        }
        #expect(source.content?.literalValue != "Deep")
    }

    @Test("A path that names nothing inside the source fails the line and changes nothing")
    func anUnknownPathFailsTheLine() throws {
        let doc = try makeDocument()
        let before = doc.childIDs(of: "Cnv01")

        let report = try apply(
            """
            {"op":"cp","source":"Component","parent":"Canvas",\
            "props":{"common.name":"Chip","Nowhere/kind.content":"Hello"}}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[0].error?.contains("Nowhere") == true)
        #expect(doc.childIDs(of: "Cnv01") == before)
    }

    // MARK: - `each`

    @Test("An each array makes one copy per row, each dressed from its own row")
    func eachMakesOneCopyPerRow() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Component","parent":"Canvas/Cards","each":[\
            {"common.name":"Chip A","Label/kind.content":"Alpha"},\
            {"common.name":"Chip B","Label/kind.content":"Beta"}]}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let created = report.lines[0].created
        try #require(created.count == 2)
        #expect(created.map(\.name) == ["Chip A", "Chip B"])
        #expect(overrides(of: doc.node(id: created[0].id))["Lbl01"]?
            .properties["content"] == .string("Alpha"))
        #expect(overrides(of: doc.node(id: created[1].id))["Lbl01"]?
            .properties["content"] == .string("Beta"))
        #expect(doc.childIDs(of: "Crd01") == ["Cd101", "Cd201", created[0].id, created[1].id])
    }

    @Test("`props` are the defaults every row starts from, and a row key wins")
    func propsAreRowDefaults() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Component","parent":"Canvas/Cards",\
            "props":{"Label/kind.content":"Shared"},\
            "each":[{"common.name":"Kept"},{"common.name":"Own","Label/kind.content":"Mine"}]}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let created = report.lines[0].created
        try #require(created.count == 2)
        #expect(overrides(of: doc.node(id: created[0].id))["Lbl01"]?
            .properties["content"] == .string("Shared"))
        #expect(overrides(of: doc.node(id: created[1].id))["Lbl01"]?
            .properties["content"] == .string("Mine"))
    }

    @Test("{n} counts the rows, from 1")
    func placeholderCountsRows() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Canvas/Cards/First","parent":"Canvas/Cards",\
            "each":[{"common.name":"Bar {n}"},{"common.name":"Bar {n}"},{"common.name":"Bar {n}"}]}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        #expect(report.lines[0].created.map(\.name) == ["Bar 1", "Bar 2", "Bar 3"])
    }

    @Test("`at` places the rows in order from the given index")
    func atPlacesRowsInOrder() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Canvas/Cards/First","parent":"Canvas/Cards","at":0,\
            "each":[{"common.name":"A"},{"common.name":"B"}]}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let created = report.lines[0].created
        try #require(created.count == 2)
        #expect(doc.childIDs(of: "Crd01") == [created[0].id, created[1].id, "Cd101", "Cd201"])
    }

    @Test("A bad key in one row discards every copy the line would have made")
    func aBadRowDiscardsTheWholeLine() throws {
        let doc = try makeDocument()
        let before = doc.childIDs(of: "Crd01")

        let report = try apply(
            """
            {"op":"cp","source":"Component","parent":"Canvas/Cards","each":[\
            {"common.name":"Good"},\
            {"common.name":"Bad","Nowhere/kind.content":"Boom"}]}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("row 2"), "the message must name the row: \(message)")
        #expect(message.contains("Nowhere"), "the message must name the key: \(message)")
        #expect(doc.childIDs(of: "Crd01") == before, "nothing was written")
    }

    @Test("An empty each array is refused rather than quietly copying nothing")
    func anEmptyEachIsRefused() throws {
        let doc = try makeDocument()

        let report = try apply(
            #"{"op":"cp","source":"Component","parent":"Canvas/Cards","each":[]}"#,
            to: doc
        )

        #expect(report.lines[0].status == .failed)
        #expect(report.lines[0].error?.contains("each") == true)
    }

    @Test("A tag on an each line is refused: one tag cannot name several copies")
    func aTagWithEachIsRefused() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Component","parent":"Canvas/Cards","tag":"chips",\
            "each":[{"common.name":"A"},{"common.name":"B"}]}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .failed)
        let message = try #require(report.lines[0].error)
        #expect(message.contains("tag"))
        #expect(message.contains("each"))
    }

    @Test("An each line round-trips through the grammar")
    func eachRoundTrips() throws {
        let written = """
        {"op":"cp","source":"Component","parent":"Canvas/Cards","each":[\
        {"common.name":"A"},{"common.name":"B"}]}
        """

        let operations = try BatchOperation.decodeJSONL(written)
        let again = try BatchOperation.decodeJSONL(BatchOperation.encodeJSONL(operations))

        #expect(operations == again)
        guard case let .cp(op) = operations[0] else {
            Issue.record("not a cp")
            return
        }
        #expect(op.each?.count == 2)
    }

    // MARK: - `"parent":"document"`

    @Test("A batch add takes \"document\" as the document root, as the verbs do")
    func addTakesTheDocumentRoot() throws {
        let doc = try makeDocument()

        let report = try apply(
            #"{"op":"add","parent":"document","node":{"type":"frame","name":"Root2"}}"#,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        let created = try #require(report.lines[0].created.first)
        #expect(doc.rootOrder.contains(created.id))
    }

    @Test("A batch cp and mv take \"document\" too")
    func copyAndMoveTakeTheDocumentRoot() throws {
        let doc = try makeDocument()

        let report = try apply(
            """
            {"op":"cp","source":"Canvas/Cards/First","parent":"document","props":{"common.name":"Loose"}}
            {"op":"mv","target":"Canvas/Cards/Second","parent":"document"}
            """,
            to: doc
        )

        #expect(report.lines[0].status == .applied, "\(report.lines[0].error ?? "")")
        #expect(report.lines[1].status == .applied, "\(report.lines[1].error ?? "")")
        #expect(doc.rootOrder.contains("Cd201"))
    }

    @Test("A parent written \"document\" encodes back as \"document\"")
    func theDocumentRootRoundTrips() throws {
        let written = #"{"op":"add","parent":"document","node":{"name":"Root2","type":"frame"}}"#

        let operations = try BatchOperation.decodeJSONL(written)
        guard case let .add(op) = operations[0] else {
            Issue.record("not an add")
            return
        }
        #expect(op.parent == nil, "\"document\" is the absence of a parent, as it is on argv")
    }
}
