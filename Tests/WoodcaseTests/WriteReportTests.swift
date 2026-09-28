//
//  WriteReportTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``WriteReport`` is a mutating verb's answer as a value: a library caller — the
/// scripting host, tomorrow — needs it without a hand-written twin, so it has to be a
/// public, `Codable` type in `Woodcase` itself rather than something only the command
/// core can construct.
@Suite("Write report as a library value")
struct WriteReportTests {
    private var title: PenNode {
        PenNode(id: "Ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData()))
    }

    @Test("A write report round-trips through JSON")
    func roundTrips() throws {
        let report = WriteReport(
            created: [CreatedNode(id: "k2Bq9", name: "Hero", children: [
                CreatedNode(id: "Tz01m", name: "Caption"),
            ])],
            path: "Hero",
            id: "k2Bq9",
            nodeRevision: "1111111111111111",
            documentRevision: "2222222222222222",
            warnings: ["Hero (k2Bq9)  0,0 900×60 sits partly outside Cards"],
            node: title,
            divergences: [WriteDivergence(
                kind: .coercion, target: "kind.content", requested: "3", applied: "\"3\"",
                note: "kind.content stored the number 3 as the text \"3\""
            )]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(WriteReport.self, from: data)

        #expect(decoded == report)
    }

    @Test("Two reports built from the same facts are equal")
    func equatable() {
        let one = WriteReport(path: "Canvas/Title", id: "Ttl01", documentRevision: "2222222222222222")
        let other = WriteReport(path: "Canvas/Title", id: "Ttl01", documentRevision: "2222222222222222")
        #expect(one == other)
    }

    @Test("A dry run drops both revisions and carries the marker")
    func dryRunDropsRevisions() {
        let report = WriteReport(
            path: "Canvas/Title", id: "Ttl01", nodeRevision: "rev", documentRevision: "doc", dryRun: true
        )
        #expect(report.nodeRevision == nil)
        #expect(report.documentRevision == nil)
        #expect(report.dryRun == true)
    }
}
