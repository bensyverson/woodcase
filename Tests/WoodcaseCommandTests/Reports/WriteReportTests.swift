//
//  WriteReportTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Pins the bytes every mutating verb answers with, so the six verbs cannot drift
/// into six shapes.
@Suite("What a write answers with")
struct WriteReportTests {
    @Test("A verb that created a subtree prints the tree, then the revisions")
    func createdSubtree() {
        let report = WriteReport(
            created: [CreatedNode(id: "k2Bq9", name: "Hero", children: [
                CreatedNode(id: "Tz01m", name: "Caption"),
            ])],
            path: "Hero",
            id: "k2Bq9",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222"
        )

        #expect(report.text == """
        Hero  k2Bq9
          Caption  Tz01m
        rev  1111111111111111
        document  2222222222222222
        """)
    }

    @Test("A verb that changed a node prints the path, the id, then the revisions")
    func changedNode() {
        let report = WriteReport(
            path: "Canvas/Title",
            id: "Ttl01",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222"
        )

        #expect(report.text == """
        Canvas/Title  Ttl01
        rev  1111111111111111
        document  2222222222222222
        """)
    }

    @Test("A verb that removed a node prints no node revision — there is no node")
    func removedNode() {
        let report = WriteReport(
            path: "Canvas/Title",
            id: "Ttl01",
            documentRevision: "2222222222222222"
        )

        #expect(report.text == """
        Canvas/Title  Ttl01
        document  2222222222222222
        """)
    }

    @Test("--json carries the same facts under stable keys")
    func jsonShape() throws {
        let report = WriteReport(
            created: [CreatedNode(id: "k2Bq9", name: "Hero")],
            path: "Hero",
            id: "k2Bq9",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222"
        )
        let json = try report.json()
        let decoded = try JSONDecoder().decode(WriteReport.self, from: Data(json.utf8))

        #expect(decoded == report)
        #expect(json.contains("\"documentRevision\""))
        #expect(json.contains("\"nodeRevision\""))
        #expect(json.contains("\"created\""))
    }

    @Test("A report with nothing created leaves the key out rather than printing []")
    func jsonOmitsEmptyCreated() throws {
        let report = WriteReport(path: "Canvas/Title", id: "Ttl01", documentRevision: "2222222222222222")
        let json = try report.json()

        #expect(!json.contains("\"created\""))
        #expect(!json.contains("\"nodeRevision\""))
    }

    // MARK: - The divergence echo

    private var title: PenNode {
        PenNode(id: "Ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData()))
    }

    /// The golden for the quiet case: when requested, applied and stored agree, a
    /// write prints the bytes it printed before the echo existed — the post-state node
    /// it now carries is for `--json` only.
    @Test("A write that diverged from nothing prints exactly the report it always did")
    func agreementPrintsTheOldReport() {
        let report = WriteReport(
            path: "Canvas/Title",
            id: "Ttl01",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222",
            node: title,
            divergences: []
        )

        #expect(report.text == """
        Canvas/Title  Ttl01
        rev  1111111111111111
        document  2222222222222222
        """)
    }

    @Test("A divergence prints between what was touched and the revisions")
    func divergencePrintsAfterThePath() {
        let report = WriteReport(
            path: "Canvas/Title",
            id: "Ttl01",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222",
            divergences: [WriteDivergence(
                kind: .coercion, target: "kind.content", requested: "3", applied: "\"3\"",
                note: "kind.content stored the number 3 as the text \"3\""
            )]
        )

        #expect(report.text == """
        Canvas/Title  Ttl01
        kind.content stored the number 3 as the text "3"
        rev  1111111111111111
        document  2222222222222222
        """)
    }

    @Test("--json carries the post-state node, so a caller can diff it itself")
    func jsonCarriesThePostStateNode() throws {
        let report = WriteReport(
            path: "Canvas/Title",
            id: "Ttl01",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222",
            node: title
        )
        let json = try report.json()
        let decoded = try JSONDecoder().decode(WriteReport.self, from: Data(json.utf8))

        #expect(decoded.node == title)
        #expect(json.contains("\"node\""))
    }

    @Test("A report with no divergences leaves the key out rather than printing []")
    func jsonOmitsEmptyDivergences() throws {
        let report = WriteReport(path: "Canvas/Title", id: "Ttl01", documentRevision: "2222222222222222")

        #expect(try !report.json().contains("\"divergences\""))
    }
}
