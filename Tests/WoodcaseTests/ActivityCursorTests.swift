//
//  ActivityCursorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins ``ActivityCursor``: a position in the log that names the *file* by inode as well
/// as the byte, so a resume survives the log being rotated in between.
@Suite(.hangGuard)
struct ActivityCursorTests {
    private func withTemporaryHome<T>(_ body: (URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityCursorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        return try await body(directory)
    }

    private static func event(_ revision: String) -> ActivityEvent {
        ActivityEvent(
            time: Date(),
            identity: "logger",
            file: URL(fileURLWithPath: "/Users/agent/Designs/demo.pen"),
            op: .set,
            nodes: ["jSUCH"],
            paths: ["layout-vertical/child-1"],
            revision: revision
        )
    }

    /// Rotates exactly as ``ActivityLog`` does: renames the live file aside.
    private static func rotate(_ log: ActivityLog, stamp: String) throws {
        try FileManager.default.moveItem(
            at: log.fileURL,
            to: log.home.appendingPathComponent("activity.\(stamp).jsonl")
        )
    }

    // MARK: - Token

    @Test("A cursor round-trips through its token")
    func tokenRoundTrips() {
        let cursor = ActivityCursor(inode: 0x1A2B3C, offset: 4096)
        #expect(cursor.token == "1a2b3c-4096")
        #expect(ActivityCursor(token: cursor.token) == cursor)
    }

    @Test("A malformed token is not a cursor", arguments: ["", "12", "zz-1", "1-x", "1-2-3", "-5"])
    func malformedTokensAreRejected(token: String) {
        #expect(ActivityCursor(token: token) == nil)
    }

    // MARK: - Resuming across rotation

    @Test("A page carries the cursor to resume from")
    func pageCarriesACursor() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event("r1"), Self.event("r2")])
            let reader = ActivityReader(log: log)
            let page = try reader.read()
            let cursor = try #require(page.cursor)
            #expect(cursor.offset == page.nextOffset)

            try await log.append([Self.event("r3")])
            let next = try reader.read(after: cursor)
            #expect(next.events.map(\.revision) == ["r3"])
            #expect(!next.restarted)
        }
    }

    @Test("A cursor taken before rotation resumes with no gaps or repeats")
    func resumesAcrossARotation() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event("r1"), Self.event("r2"), Self.event("r3")])
            // The cursor is *inside* the log: after r2, with r3 still unread.
            let pageBefore = try reader.read()
            let afterSecond = try #require(pageBefore.eventCursors[safe: 1])

            try Self.rotate(log, stamp: "20260829T000000Z")
            try await log.append([Self.event("r4"), Self.event("r5")])

            let page = try reader.read(after: afterSecond)
            #expect(page.events.map(\.revision) == ["r3", "r4", "r5"])
            #expect(!page.restarted, "a rotation the cursor follows loses nothing")

            // And resuming from where that page ended repeats nothing.
            let again = try reader.read(after: #require(page.cursor))
            #expect(again.events.isEmpty)
            #expect(!again.restarted)
        }
    }

    @Test("Two rotations between reads still lose nothing")
    func resumesAcrossTwoRotations() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event("r1")])
            let cursor = try #require(reader.read().cursor)

            try Self.rotate(log, stamp: "20260829T000000Z")
            try await log.append([Self.event("r2")])
            try Self.rotate(log, stamp: "20260829T000100Z")
            try await log.append([Self.event("r3")])

            let page = try reader.read(after: cursor)
            #expect(page.events.map(\.revision) == ["r2", "r3"])
        }
    }

    @Test("A cursor whose archive is gone restarts from the live log and says so")
    func missingArchiveRestarts() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event("r1")])
            let cursor = try #require(reader.read().cursor)

            try Self.rotate(log, stamp: "20260829T000000Z")
            try FileManager.default.removeItem(
                at: home.appendingPathComponent("activity.20260829T000000Z.jsonl")
            )
            try await log.append([Self.event("r2")])

            let page = try reader.read(after: cursor)
            #expect(page.events.map(\.revision) == ["r2"])
            #expect(page.restarted)
        }
    }

    @Test("The start cursor reads the whole history, archives included")
    func startCursorReadsEverything() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            #expect(try reader.read().cursor == .start)

            try await log.append([Self.event("r1")])
            try Self.rotate(log, stamp: "20260829T000000Z")
            try await log.append([Self.event("r2")])

            let page = try reader.read(after: .start)
            #expect(page.events.map(\.revision) == ["r1", "r2"])
        }
    }

    // MARK: - Follow

    @Test("A follow's iterator exposes the cursor after each event")
    func followExposesTheCursorAfterEachEvent() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            try await log.append([Self.event("r1"), Self.event("r2"), Self.event("r3")])
            let reader = ActivityReader(log: log)

            let taken = try await BoundedWait.value { () -> (String, ActivityCursor) in
                var iterator = reader.follow(pollInterval: .milliseconds(10)).makeAsyncIterator()
                let first = await iterator.next()
                return (first?.revision ?? "", iterator.cursor)
            }
            #expect(taken.0 == "r1")

            // The cursor sits after r1 even though the same read held r2 and r3.
            let rest = try reader.read(after: taken.1)
            #expect(rest.events.map(\.revision) == ["r2", "r3"])
        }
    }

    @Test("A follow resumed from a cursor continues across a rotation")
    func followResumesAcrossARotation() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event("r1")])
            let cursor = try #require(reader.read().cursor)

            try Self.rotate(log, stamp: "20260829T000000Z")
            try await log.append([Self.event("r2")])

            let seen = try await BoundedWait.value { () -> [String] in
                var iterator = reader.follow(after: cursor, pollInterval: .milliseconds(10))
                    .makeAsyncIterator()
                return await [iterator.next()?.revision ?? ""]
            }
            #expect(seen == ["r2"])
        }
    }

    @Test("A follow's cursor stays exact when the log rotates under it")
    func followCursorSurvivesARotationMidFeed() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event("r1")])

            let (revisions, cursor) = try await BoundedWait.value { () -> ([String], ActivityCursor) in
                var iterator = reader.follow(pollInterval: .milliseconds(10)).makeAsyncIterator()
                let first = await iterator.next()?.revision ?? ""
                try? Self.rotate(log, stamp: "20260829T000000Z")
                try? await log.append([Self.event("r2"), Self.event("r3")])
                let second = await iterator.next()?.revision ?? ""
                return ([first, second], iterator.cursor)
            }
            #expect(revisions == ["r1", "r2"])

            let rest = try reader.read(after: cursor)
            #expect(rest.events.map(\.revision) == ["r3"])
            #expect(!rest.restarted)
        }
    }

    @Test("A follow from an offset taken just before a rotation resumes in the archive, not from the top")
    func followFromAnOffsetMidRotation() async throws {
        try await withTemporaryHome { home in
            let log = ActivityLog(home: home)
            let reader = ActivityReader(log: log)
            try await log.append([Self.event("r1"), Self.event("r2")])
            let afterFirst = try #require(reader.read().eventCursors.first).offset

            // Renamed aside and not yet recreated: the instant inside ActivityLog's rotation.
            try Self.rotate(log, stamp: "20260829T000000Z")

            let first = try await BoundedWait.value { () -> String in
                var iterator = reader.follow(from: afterFirst, pollInterval: .milliseconds(10))
                    .makeAsyncIterator()
                return await iterator.next()?.revision ?? ""
            }
            #expect(first == "r2", "the offset is into the newest archive; r1 must not replay")
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
