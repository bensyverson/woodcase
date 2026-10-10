//
//  JSONLinesFileSinceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins the two reads ``PenFileFollower/Start/since(_:)`` stands on: finding where a
/// time window starts by walking the log backward — into the archives only when the live
/// file starts inside the window — and reading the history up to a fixed end, so what is
/// written after that end is left whole for the live read.
@Suite(.hangGuard)
struct JSONLinesFileSinceTests {
    /// A scratch log home.
    private struct Scratch {
        let home: URL
        let log: ActivityLog
        let now = Date()

        init() {
            home = FileManager.default.temporaryDirectory
                .appendingPathComponent("JSONLinesFileSinceTests-\(UUID().uuidString)", isDirectory: true)
            log = ActivityLog(home: home)
        }

        func remove() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [] {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: home.appendingPathComponent(name).path
                )
            }
            try? FileManager.default.removeItem(at: home)
        }

        func ago(_ minutes: Double) -> Date {
            now.addingTimeInterval(-minutes * 60)
        }

        func row(_ revision: String, at time: Date, padding: Int = 0) -> ActivityEvent {
            ActivityEvent(
                time: time, identity: "claude", file: URL(fileURLWithPath: "/tmp/design.pen"), op: .set,
                paths: padding > 0 ? [String(repeating: "x", count: padding)] : [], revision: revision
            )
        }

        func line(_ row: ActivityEvent) throws -> Data {
            var line = try row.jsonLine()
            line.append(JSONLinesFile.newline)
            return line
        }

        /// The archives then the live file, oldest first.
        var files: [URL] {
            log.lines.archives().map(\.url) + [log.fileURL]
        }

        func inode(_ url: URL) throws -> UInt64 {
            try #require(FileSignature.read(at: url.path)).inode
        }

        func read(after cursor: ActivityCursor, through end: ActivityCursor, since date: Date = .distantPast) throws -> JSONLinesPage<ActivityEvent> {
            try log.lines.read(after: cursor, through: end, since: date) { (_: ActivityEvent) in true }
        }
    }

    @Test("A window inside the live file starts after its newest older row, and never opens an archive")
    func boundaryInTheLiveFileLeavesArchivesShut() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        let old = scratch.row("r1", at: scratch.ago(30))
        try FollowHistory.write([
            [scratch.row("a1", at: scratch.ago(90))],
            [old, scratch.row("r2", at: scratch.ago(5))],
        ], to: scratch.log)
        let archive = try #require(scratch.files.first)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: archive.path)

        let cursor = try scratch.log.lines.cursor(since: scratch.ago(10), through: scratch.log.lines.endCursor())

        #expect(try cursor == ActivityCursor(inode: scratch.inode(scratch.log.fileURL), offset: UInt64(scratch.line(old).count)))
        // A window older than the live file's first row has to open it.
        #expect(throws: PenFileError.self) {
            try scratch.log.lines.cursor(since: scratch.ago(60), through: scratch.log.lines.endCursor())
        }
    }

    @Test("A window that starts inside an archive names that archive, just after its newest older row")
    func boundaryInsideAnArchive() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        let rows = [scratch.row("a1", at: scratch.ago(180)), scratch.row("a2", at: scratch.ago(120))]
        try FollowHistory.write([
            rows + [scratch.row("a3", at: scratch.ago(15))],
            [scratch.row("r1", at: scratch.ago(5))],
        ], to: scratch.log)

        let cursor = try scratch.log.lines.cursor(since: scratch.ago(60), through: scratch.log.lines.endCursor())

        let offset = try rows.reduce(0) { try $0 + (scratch.line($1).count) }
        #expect(try cursor == ActivityCursor(inode: scratch.inode(scratch.files[0]), offset: UInt64(offset)))
    }

    @Test("A date before every row starts at the beginning; one after every row starts at the end")
    func datesOutsideTheHistory() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([
            [scratch.row("a1", at: scratch.ago(180))],
            [scratch.row("r1", at: scratch.ago(5))],
        ], to: scratch.log)
        let end = scratch.log.lines.endCursor()

        #expect(try scratch.log.lines.cursor(since: scratch.ago(600), through: end) == .start)
        #expect(try scratch.log.lines.cursor(since: scratch.now, through: end) == end)
    }

    @Test("The end of a file holding a half-written line is the end of the last whole line")
    func endCursorStopsBeforeAPartialLine() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        let first = scratch.row("r1", at: scratch.ago(5))
        try FollowHistory.write([[first]], to: scratch.log)
        let handle = try FileHandle(forWritingTo: scratch.log.fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: scratch.line(scratch.row("r2", at: Date())).prefix(20))

        let end = scratch.log.lines.endCursor()

        #expect(try end == ActivityCursor(inode: scratch.inode(scratch.log.fileURL), offset: UInt64(scratch.line(first).count)))
    }

    @Test("A window row filed behind a slightly older row is still found; the older row is not delivered")
    func slightlyOutOfOrderRowsAreFound() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        let date = scratch.ago(10)
        let old = scratch.row("old", at: scratch.ago(60))
        try FollowHistory.write([[
            old,
            scratch.row("inside", at: date.addingTimeInterval(0.2)),
            scratch.row("stamped-earlier", at: date.addingTimeInterval(-1)),
            scratch.row("later", at: scratch.ago(2)),
        ]], to: scratch.log)
        let end = scratch.log.lines.endCursor()

        let start = try scratch.log.lines.cursor(since: date, through: end)
        let page = try scratch.read(after: start, through: end, since: date)

        #expect(try start.offset == UInt64(scratch.line(old).count))
        #expect(page.rows.map(\.revision) == ["inside", "later"])
    }

    @Test("Lines longer than the walk's chunk are found whole")
    func linesLongerThanAChunk() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        let rows = [
            scratch.row("r1", at: scratch.ago(30), padding: 150_000),
            scratch.row("r2", at: scratch.ago(20), padding: 150_000),
            scratch.row("r3", at: scratch.ago(5), padding: 150_000),
        ]
        try FollowHistory.write([rows], to: scratch.log)

        let cursor = try scratch.log.lines.cursor(since: scratch.ago(10), through: scratch.log.lines.endCursor())

        let offset = try rows.prefix(2).reduce(0) { try $0 + (scratch.line($1).count) }
        #expect(cursor.offset == UInt64(offset))
    }

    @Test("A read through an end stops there, and resuming from its cursor reads what came after, once")
    func boundedReadStopsAtTheEnd() async throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([
            [scratch.row("a1", at: scratch.ago(30))],
            [scratch.row("r1", at: scratch.ago(5))],
        ], to: scratch.log)
        let end = scratch.log.lines.endCursor()
        try await scratch.log.append([scratch.row("r2", at: Date())])

        let history = try scratch.read(after: .start, through: end)
        #expect(history.rows.map(\.revision) == ["a1", "r1"])
        #expect(history.cursor == end)

        let live: JSONLinesPage<ActivityEvent> = try scratch.log.lines.read(after: #require(history.cursor)) { _ in true }
        #expect(live.rows.map(\.revision) == ["r2"])
    }

    @Test("A read through an end keeps only rows at or after the date")
    func boundedReadFiltersByTime() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([[
            scratch.row("r1", at: scratch.ago(5)),
            scratch.row("late", at: scratch.ago(20)),
            scratch.row("r2", at: scratch.ago(4)),
        ]], to: scratch.log)

        let page = try scratch.read(after: .start, through: scratch.log.lines.endCursor(), since: scratch.ago(10))

        #expect(page.rows.map(\.revision) == ["r1", "r2"])
    }

    @Test("An end that falls inside a line being written leaves that line whole for the next read")
    func endInsideAPartialLine() throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([[scratch.row("r1", at: scratch.ago(5))]], to: scratch.log)
        let first = try scratch.line(scratch.row("r1", at: scratch.ago(5)))
        let second = try scratch.line(scratch.row("r2", at: Date()))
        let handle = try FileHandle(forWritingTo: scratch.log.fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: second.prefix(20))
        let end = scratch.log.lines.endCursor()

        let start = try scratch.log.lines.cursor(since: scratch.ago(10), through: end)
        let history = try scratch.read(after: start, through: end)
        try handle.write(contentsOf: second.dropFirst(20))
        let live: JSONLinesPage<ActivityEvent> = try scratch.log.lines.read(after: #require(history.cursor)) { _ in true }

        #expect(start.offset == 0)
        #expect(history.rows.map(\.revision) == ["r1"])
        #expect(history.cursor?.offset == UInt64(first.count))
        #expect(live.rows.map(\.revision) == ["r2"])
    }

    @Test("A read through an end in a file rotated since stops in the archive, and the live file is left for later")
    func boundedReadAcrossARotation() async throws {
        let scratch = Scratch()
        defer { scratch.remove() }
        try FollowHistory.write([[scratch.row("r1", at: scratch.ago(5))]], to: scratch.log)
        let end = scratch.log.lines.endCursor()
        try FileManager.default.moveItem(
            at: scratch.log.fileURL,
            to: scratch.home.appendingPathComponent("activity.20260101T000009Z.jsonl")
        )
        try await scratch.log.append([scratch.row("r2", at: Date())])

        let history = try scratch.read(after: .start, through: end)
        let live: JSONLinesPage<ActivityEvent> = try scratch.log.lines.read(after: #require(history.cursor)) { _ in true }

        #expect(history.rows.map(\.revision) == ["r1"])
        #expect(live.rows.map(\.revision) == ["r2"])
    }
}
