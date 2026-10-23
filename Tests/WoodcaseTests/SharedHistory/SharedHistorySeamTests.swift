//
//  SharedHistorySeamTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Every row records the revision it started from as well as the one it produced, so a
/// change made outside the log — Pen.app, a hand edit, a Git merge — shows as a seam:
/// an `external` row from the last recorded revision to the one found.
struct SharedHistorySeamTests {
    private typealias Fixture = SharedHistoryFixture

    @Test("a row records the revision it started from")
    func rowsRecordTheirParent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let before = try fixture.revision()

        try await PenFileTransaction.run(at: fixture.bundle, identity: "ben", log: fixture.log()) { _, recorder in
            try recorder.apply(Fixture.rename("One"))
            try recorder.apply(Fixture.rename("Two"))
        }

        let rows = try ActivityReader(log: fixture.log()).read().events
        #expect(rows.count == 2)
        #expect(rows.first?.parent == before)
        #expect(rows.last?.parent == rows.first?.revision)
        #expect(try rows.last?.revision == fixture.revision())
    }

    @Test("a change outside the log is recorded as a seam before the next write")
    func outsideChangeLeavesASeam() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await PenFileTransaction.run(at: fixture.bundle, identity: "ben", log: log) { _, recorder in
            try recorder.apply(Fixture.rename("By Ben"))
        }
        let recorded = try fixture.revision()
        try fixture.editOutsideTheLog(name: "By Pen")
        let found = try fixture.revision()

        let outcome = try await PenFileTransaction.run(at: fixture.bundle, identity: "claude", log: log) { _, recorder in
            try recorder.apply(Fixture.rename("By Claude"))
        }

        #expect(outcome.lineage.isDiverged)
        let rows = try ActivityReader(log: log).read().events
        #expect(rows.map(\.op) == [.set, .external, .set])
        let seam = rows[1]
        #expect(seam.parent == recorded)
        #expect(seam.revision == found)
        #expect(seam.identity == ActivityEvent.unattributed)
        #expect(rows[2].parent == found)
        let claudes = try String(contentsOf: fixture.history.appendingPathComponent("claude@grace.jsonl"), encoding: .utf8)
        #expect(claudes.contains("\"op\":\"external\""))
    }

    @Test("any writer's newest row explains the file, whatever the clocks say")
    func anyWriterExplainsTheFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let current = try fixture.revision()
        // A device whose clock runs ahead wrote earlier; this one wrote the file last.
        try await fixture.log(device: "grace").append(
            [Fixture.event("ben", at: 0, file: fixture.bundle, revision: current)], as: "ben"
        )
        try await fixture.log(device: "hopper").append(
            [Fixture.event("ben", at: 1000, file: fixture.bundle, revision: "elsewhere")], as: "ben"
        )

        let lineage = try LogLineage.read(fixture.bundle, at: current, from: fixture.log())

        #expect(!lineage.isDiverged)
        #expect(lineage.newest?.revision == current)
    }

    @Test("a session's rows record the revision each change started from")
    func sessionRowsRecordTheirParent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let before = try fixture.revision()
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: fixture.bundle),
            author: Author(name: "ben", peerID: PeerID(rawValue: "peer-ben")),
            file: fixture.bundle, merger: .threeWay
        )

        let first = try session.submit(.local(LocalEdit(operations: [Fixture.rename("A")])))
        let second = try session.submit(.local(LocalEdit(operations: [Fixture.rename("B"), Fixture.rename("C")])))

        #expect(first.activity.map(\.parent) == [before])
        #expect(second.activity.map(\.parent) == [first.activity[0].revision, second.activity[0].revision])
    }

    @Test("a folded row starts from its run's first parent")
    func foldingKeepsTheFirstParent() {
        var one = Fixture.event("ben", at: 1, file: URL(fileURLWithPath: "/tmp/a.pen"), revision: "r1")
        one.parent = "r0"
        var two = Fixture.event("ben", at: 2, file: URL(fileURLWithPath: "/tmp/a.pen"), revision: "r2")
        two.parent = "r1"

        let folded = ActivityEvent.folding([one, two])

        #expect(folded.map(\.parent) == ["r0"])
        #expect(folded.map(\.revision) == ["r2"])
    }

    @Test("parent is on the wire as \"parent\", omitted when unknown")
    func parentOnTheWire() throws {
        var row = Fixture.event("ben", at: 1, file: URL(fileURLWithPath: "/tmp/a.pen"), revision: "r1")
        #expect(try !String(decoding: row.jsonLine(), as: UTF8.self).contains("parent"))

        row.parent = "r0"
        let line = try row.jsonLine()

        #expect(String(decoding: line, as: UTF8.self).contains("\"parent\":\"r0\""))
        #expect(try ActivityEvent(line: line) == row)
    }
}
