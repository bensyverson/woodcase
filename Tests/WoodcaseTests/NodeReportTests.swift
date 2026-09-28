//
//  NodeReportTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``NodeReport`` is the `--json` shape of `woodcase get` as a value: the scripting
/// host's `doc.get(...)` returns exactly this, so it must be a public, `Codable` type
/// in `Woodcase` rather than a command-core-only struct.
@Suite("Node report as a library value")
struct NodeReportTests {
    private var title: PenNode {
        PenNode(id: "Ttl01", common: PenNodeCommon(name: "Title"), kind: .text(PenNode.TextData()))
    }

    @Test("A node report round-trips through JSON")
    func roundTrips() throws {
        let report = NodeReport(
            revision: "abc123",
            node: title,
            props: [ComponentParameter(name: "label", path: "Body/Title")]
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(NodeReport.self, from: data)

        #expect(decoded == report)
    }

    @Test("A node with no published parameters omits the key when re-encoded")
    func equatableWithoutProps() {
        let one = NodeReport(revision: "abc123", node: title)
        let other = NodeReport(revision: "abc123", node: title, props: nil)
        #expect(one == other)
        #expect(one.props == nil)
    }
}
