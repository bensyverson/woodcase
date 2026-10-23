//
//  SharedHistoryReaderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Every reader of a bundle's history sees all writers' rows merged in time order:
/// ties go to the writer whose file name sorts first, and each writer's own rows keep
/// the order they were appended in.
struct SharedHistoryReaderTests {
    private typealias Fixture = SharedHistoryFixture

    /// The rows' times, as seconds after the fixture's moment.
    private static func seconds(_ rows: [ActivityEvent]) -> [TimeInterval] {
        rows.map { $0.time.timeIntervalSince1970 - 1_800_000_000 }
    }

    @Test("rows from two writers read back in time order")
    func mergesByTime() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([Fixture.event("ana", at: 1, file: fixture.bundle), Fixture.event("ana", at: 3, file: fixture.bundle)], as: "ana")
        try await log.append([Fixture.event("ben", at: 2, file: fixture.bundle)], as: "ben")
        let reader = ActivityReader(log: log)

        #expect(try Self.seconds(reader.read().events) == [1, 2, 3])
        #expect(try Self.seconds(reader.read(after: .start).events) == [1, 2, 3])
        #expect(try Self.seconds(reader.tail(count: 2)) == [2, 3])
        #expect(try reader.read(identity: "ben").events.map(\.identity) == ["ben"])
    }

    @Test("a tie in time goes to the writer whose file sorts first")
    func breaksTiesByWriter() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([Fixture.event("zed", at: 5, file: fixture.bundle)], as: "zed")
        try await log.append([Fixture.event("ana", at: 5, file: fixture.bundle)], as: "ana")

        #expect(try ActivityReader(log: log).read().events.map(\.identity) == ["ana", "zed"])
    }

    @Test("a writer's own rows keep their order even when its clock went back")
    func keepsEachWritersOrder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([
            Fixture.event("ana", at: 5, file: fixture.bundle, revision: "first"),
            Fixture.event("ana", at: 4, file: fixture.bundle, revision: "second"),
        ], as: "ana")
        try await log.append([Fixture.event("ben", at: 4.5, file: fixture.bundle, revision: "ben")], as: "ben")

        // Merged by each file's next row, not sorted: ana's 4 never jumps ahead of her 5.
        #expect(try ActivityReader(log: log).read().events.map(\.revision) == ["ben", "first", "second"])
    }

    @Test("newest is the latest row of any writer")
    func newestAcrossWriters() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([Fixture.event("ana", at: 9, file: fixture.bundle, revision: "late")], as: "ana")
        try await log.append([Fixture.event("ben", at: 2, file: fixture.bundle, revision: "early")], as: "ben")

        #expect(try ActivityReader(log: log).newest(file: fixture.bundle)?.revision == "late")
    }

    @Test("a window since a moment takes every writer's rows in it")
    func sinceAcrossWriters() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([Fixture.event("ana", at: 1, file: fixture.bundle), Fixture.event("ana", at: 100, file: fixture.bundle)], as: "ana")
        try await log.append([Fixture.event("ben", at: 2, file: fixture.bundle), Fixture.event("ben", at: 101, file: fixture.bundle)], as: "ben")
        let reader = ActivityReader(log: log)
        let end = reader.endCursor()
        let date = Date(timeIntervalSince1970: 1_800_000_050)

        let start = try reader.cursor(since: date, through: end)
        let page = try reader.read(after: start, through: end, since: date, file: fixture.bundle)

        #expect(Self.seconds(page.events) == [100, 101])
        #expect(page.cursor == end)
    }

    @Test("following a bundle yields every writer's rows", .timeLimit(.minutes(1)))
    func followsEveryWriter() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([Fixture.event("ana", at: 2, file: fixture.bundle)], as: "ana")
        try await log.append([Fixture.event("ben", at: 1, file: fixture.bundle)], as: "ben")

        var iterator = ActivityReader(log: log).follow(after: .start, pollInterval: .milliseconds(10)).makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        #expect([first?.identity, second?.identity] == ["ben", "ana"])
    }

    @Test("the change feed sees another writer's rows")
    func changeFeedAcrossWriters() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        let feed = ChangeFeed(file: fixture.bundle, identity: "claude", log: log)
        let first = try await feed.read()
        try await feed.save(first)

        try await PenFileTransaction.run(at: fixture.bundle, identity: "ben", log: log) { _, recorder in
            try recorder.apply(Fixture.rename("By Ben"))
        }
        let report = try await feed.read()

        #expect(report.changes.map(\.identity) == ["ben"])
        #expect(fixture.historyFiles() == ["ben@grace.jsonl"])
    }

    @Test("undo with several writers: another writer's newer row blocks, its own undoes")
    func undoAcrossWriters() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        for (identity, name) in [("ana", "By Ana"), ("ben", "By Ben")] {
            try await PenFileTransaction.run(at: fixture.bundle, identity: identity, log: log) { _, recorder in
                try recorder.apply(Fixture.rename(name))
            }
        }

        let blocked = try await undo(fixture, log: log, as: "ana")
        let undone = try await undo(fixture, log: log, as: "ben")

        #expect(blocked.undone.isEmpty)
        #expect(blocked.stopped?.isBlockedByOther == true)
        #expect(undone.undone.map(\.identity) == ["ben"])
        let name = try EditableDocument(from: PenParser.parse(contentsOf: fixture.document)).nodes[Fixture.nodeID]?.common.name
        #expect(name == "By Ana")
        #expect(fixture.historyFiles() == ["ana@grace.jsonl", "ben@grace.jsonl"])
    }

    private func undo(_ fixture: Fixture, log: ActivityLog, as identity: String) async throws -> ActivityUndo.Result {
        try await PenFileTransaction.run(at: fixture.bundle, identity: identity, log: log) { document, recorder in
            try ActivityUndo.reverse(in: document, through: recorder, editing: fixture.bundle, log: log, identity: identity)
        }.value
    }
}

private extension UndoStep {
    /// Whether the walk stopped at another identity's row.
    var isBlockedByOther: Bool {
        if case .blockedByOther = self { true } else { false }
    }
}
