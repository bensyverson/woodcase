//
//  CreatedTreeReportTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``CreatedTreeReport`` is the `--json` shape of what a mutating verb made: the name →
/// id tree plus the revision it left behind. It has to be a public, `Codable` type in
/// `Woodcase` — not a type nested inside a command-core formatter — for a library
/// caller to get it as a value.
@Suite("Created-tree report as a library value")
struct CreatedTreeReportTests {
    private let card = CreatedNode(
        id: "ALu8G",
        name: "Card",
        children: [CreatedNode(id: "x9Kqp", name: "Title")]
    )

    @Test("A created-tree report round-trips through JSON")
    func roundTrips() throws {
        let report = CreatedTreeReport(created: [card], revision: "rev-9")

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CreatedTreeReport.self, from: data)

        #expect(decoded == report)
    }

    @Test("Two reports built from the same facts are equal")
    func equatable() {
        let one = CreatedTreeReport(created: [card], revision: "rev-9")
        let other = CreatedTreeReport(created: [card], revision: "rev-9")
        #expect(one == other)
    }

    @Test("A verb that created nothing still carries the revision")
    func emptyCreated() {
        let report = CreatedTreeReport(created: [], revision: "rev-9")
        #expect(report.created.isEmpty)
        #expect(report.revision == "rev-9")
    }
}
