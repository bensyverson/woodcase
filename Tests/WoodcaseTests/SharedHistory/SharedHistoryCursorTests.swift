//
//  SharedHistoryCursorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A cursor into a bundle's history holds one position per writer, so a reader resumes
/// without a gap or a repeat, and a row a sync delivers late is still read.
struct SharedHistoryCursorTests {
    private typealias Fixture = SharedHistoryFixture

    @Test("a per-writer cursor round-trips through its token")
    func tokenRoundTrips() {
        let cursor = ActivityCursor(writers: [
            "ben@grace": ActivityCursor(inode: 0x1A2B, offset: 40960),
            "claude@grace": ActivityCursor(inode: 0x3C, offset: 12),
        ])

        #expect(cursor.token == "ben@grace=1a2b-40960,claude@grace=3c-12")
        #expect(ActivityCursor(token: cursor.token) == cursor)
        #expect(ActivityCursor(token: "ben@grace=zz-1") == nil)
        #expect(ActivityCursor(token: "0-0") == .start)
        #expect(ActivityCursor(writers: [:]) == .start)
    }

    @Test("a single-file cursor's token is unchanged")
    func singleTokenUnchanged() {
        #expect(ActivityCursor(inode: 0x1A2B, offset: 40960).token == "1a2b-40960")
    }

    @Test("a page's cursor resumes after every writer's last row")
    func resumesAfterEveryWriter() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        let reader = ActivityReader(log: log)
        try await log.append([Fixture.event("ana", at: 1, file: fixture.bundle)], as: "ana")
        try await log.append([Fixture.event("ben", at: 2, file: fixture.bundle)], as: "ben")
        let page = try reader.read(after: .start)
        #expect(page.cursor?.writers.count == 2)

        try await log.append([Fixture.event("ana", at: 3, file: fixture.bundle)], as: "ana")
        let next = try reader.read(after: #require(page.cursor))

        #expect(next.events.map(\.identity) == ["ana"])
        #expect(next.restarted == false)
        #expect(try reader.read(after: #require(next.cursor)).events.isEmpty)
    }

    @Test("an event's cursor resumes just after that event, across writers")
    func eventCursorsResumeMidPage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        let reader = ActivityReader(log: log)
        try await log.append([Fixture.event("ana", at: 1, file: fixture.bundle), Fixture.event("ana", at: 3, file: fixture.bundle)], as: "ana")
        try await log.append([Fixture.event("ben", at: 2, file: fixture.bundle)], as: "ben")
        let page = try reader.read(after: .start)
        #expect(page.eventCursors.count == 3)

        let rest = try reader.read(after: page.eventCursors[0])

        #expect(rest.events.map(\.identity) == ["ben", "ana"])
    }

    @Test("a writer that appears after a cursor is read from its first row")
    func newWriterIsReadWhole() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        let reader = ActivityReader(log: log)
        try await log.append([Fixture.event("ana", at: 5, file: fixture.bundle)], as: "ana")
        let end = reader.endCursor()
        #expect(end.writers.keys.sorted() == ["ana@grace"])

        // A sync delivers another device's file, with rows older than the cursor's.
        try await fixture.log(device: "hopper").append([Fixture.event("ben", at: 1, file: fixture.bundle)], as: "ben")

        #expect(try reader.read(after: end).events.map(\.identity) == ["ben"])
    }

    @Test("the end cursor skips everything already written")
    func endCursorSkipsHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        let reader = ActivityReader(log: log)
        try await log.append([Fixture.event("ana", at: 1, file: fixture.bundle)], as: "ana")
        try await log.append([Fixture.event("ben", at: 2, file: fixture.bundle)], as: "ben")

        let end = reader.endCursor()

        #expect(end.writers.keys.sorted() == ["ana@grace", "ben@grace"])
        #expect(try reader.read(after: end).events.isEmpty)
    }

    @Test("a single-file cursor handed to a bundle starts over and says so")
    func foreignCursorRestarts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([Fixture.event("ana", at: 1, file: fixture.bundle)], as: "ana")

        let page = try ActivityReader(log: log).read(after: ActivityCursor(inode: 99, offset: 10))

        #expect(page.restarted)
        #expect(page.events.map(\.identity) == ["ana"])
        #expect(page.cursor?.writers.keys.sorted() == ["ana@grace"])
    }
}
