//
//  SharedHistoryLayoutTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A bundle's history is one append-only file per writer in `<bundle>/history/`, meant
/// to be committed: rows carry no absolute path, and the repository's `.gitignore` is
/// never touched.
struct SharedHistoryLayoutTests {
    @Test("a bundle's log is its history directory, one file per writer")
    func locatesTheHistoryDirectory() throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }

        let log = fixture.log()

        #expect(log.home.path == fixture.history.path)
        #expect(log.layout == .perWriter)
        #expect(log.stateDirectory.path == fixture.bundle.path + "/.woodcase")
        #expect(log.origin == .bundle(root: URL(fileURLWithPath: fixture.bundle.path, isDirectory: true)))
        #expect(PenLocation(fixture.bundle).historyDirectory?.path == fixture.history.path)
    }

    @Test("a bare file keeps one activity.jsonl at the repository root")
    func bareFilesKeepOneLog() throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }

        let log = ActivityLogLocation.log(for: fixture.directory.appendingPathComponent("Bare.pen"), environment: [:])

        #expect(log.layout == .single)
        #expect(log.fileURL.path == fixture.directory.path + "/.woodcase/activity.jsonl")
        #expect(log.stateDirectory == log.home)
    }

    @Test("two writers appending to one bundle write two files")
    func twoWritersTwoFiles() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }
        let log = fixture.log()

        try await log.append([SharedHistoryFixture.event("ben", at: 1, file: fixture.bundle)], as: "ben")
        try await log.append([SharedHistoryFixture.event("claude", at: 2, file: fixture.bundle)], as: "claude")

        #expect(fixture.historyFiles() == ["ben@grace.jsonl", "claude@grace.jsonl"])
    }

    @Test("one person on two devices writes two files")
    func oneIdentityTwoDevices() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }

        try await fixture.log(device: "grace").append([SharedHistoryFixture.event("ben", at: 1, file: fixture.bundle)], as: "ben")
        try await fixture.log(device: "hopper").append([SharedHistoryFixture.event("ben", at: 2, file: fixture.bundle)], as: "ben")

        #expect(fixture.historyFiles() == ["ben@grace.jsonl", "ben@hopper.jsonl"])
    }

    @Test("without an explicit writer, the batch's first named identity chooses the file")
    func derivesTheWriterFromTheRows() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }
        let external = ActivityEvent(
            time: Date(), identity: ActivityEvent.unattributed, file: fixture.bundle, op: .external, revision: "r0"
        )

        try await fixture.log().append([external, SharedHistoryFixture.event("ana", at: 1, file: fixture.bundle)])

        #expect(fixture.historyFiles() == ["ana@grace.jsonl"])
    }

    @Test("a bundle's rows carry no absolute path on disk, and read back naming the document")
    func rowsCarryNoPath() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }
        let log = fixture.log()

        try await log.append([SharedHistoryFixture.event("ben", at: 1, file: fixture.bundle)], as: "ben")

        let line = try String(contentsOf: fixture.history.appendingPathComponent("ben@grace.jsonl"), encoding: .utf8)
        #expect(!line.contains("\"file\""))
        #expect(!line.contains(fixture.directory.path))
        #expect(line.contains("\"identity\":\"ben\""))
        let rows = try ActivityReader(log: log).read().events
        #expect(rows.map(\.file) == [ActivityEvent.canonicalPath(for: fixture.bundle)])
    }

    @Test("a bundle in a repository leaves the repository's .gitignore alone")
    func leavesTheRepositoryIgnoreAlone() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }

        try await PenFileTransaction.run(at: fixture.bundle, identity: "ben", log: fixture.log()) { _, recorder in
            try recorder.apply(SharedHistoryFixture.rename("Committed"))
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(".gitignore").path))
    }

    @Test("a bundle ignores its own local state, inside itself")
    func ignoresLocalStateInsideTheBundle() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }

        try await fixture.log().append([SharedHistoryFixture.event("ben", at: 1, file: fixture.bundle)], as: "ben")

        let ignore = try String(contentsOf: fixture.bundle.appendingPathComponent(".gitignore"), encoding: .utf8)
        let lines = ignore.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains(ActivityLog.ignorePattern))
        #expect(!lines.contains("history/"))
    }

    @Test("a bare file in a repository still ignores .woodcase/ there")
    func bareFilesStillIgnoreTheirLog() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }
        let bare = fixture.directory.appendingPathComponent("Bare.pen")

        try await ActivityLogLocation.log(for: bare, environment: [:])
            .append([SharedHistoryFixture.event("ben", at: 1, file: bare)])

        let ignore = try String(contentsOf: fixture.directory.appendingPathComponent(".gitignore"), encoding: .utf8)
        #expect(ignore.contains(ActivityLog.ignorePattern))
    }

    @Test("views and cursors stay in the bundle's local .woodcase, not in its history")
    func localStateStaysLocal() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }
        let log = fixture.log()

        try await ViewLog(beside: log).record(ViewEvent(
            identity: "claude", file: fixture.bundle, verb: .get, revision: "r", nodes: ["a"], scope: .nodes
        ))
        try await ActivityCursorStore(log: log).save(.start, identity: "claude", file: fixture.bundle)

        #expect(fixture.historyFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.bundle.path + "/.woodcase/views.jsonl"))
        #expect(FileManager.default.fileExists(atPath: fixture.bundle.path + "/.woodcase/cursors"))
    }

    @Test("an old single log inside a bundle is ignored")
    func ignoresALegacyLog() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }
        let legacy = ActivityLog(home: fixture.bundle.appendingPathComponent(".woodcase"))
        try await legacy.append([SharedHistoryFixture.event("ana", at: 1, file: fixture.bundle)])

        #expect(try ActivityReader(log: fixture.log()).read().events.isEmpty)
    }

    @Test("a writer's file rotates on its own, and the reader still sees every row")
    func rotatesPerWriter() async throws {
        let fixture = try SharedHistoryFixture()
        defer { fixture.remove() }
        let log = fixture.log()
        try await log.append([SharedHistoryFixture.event("ben", at: 1, file: fixture.bundle)], as: "ben")
        let live = fixture.history.appendingPathComponent("ben@grace.jsonl")
        let archive = fixture.history.appendingPathComponent("ben@grace.20260101T000000Z.jsonl")
        try FileManager.default.moveItem(at: live, to: archive)
        try await log.append([SharedHistoryFixture.event("ben", at: 2, file: fixture.bundle)], as: "ben")

        let rows = try ActivityReader(log: log).read(after: .start).events

        #expect(rows.map(\.time.timeIntervalSince1970) == [1_800_000_001, 1_800_000_002])
    }
}
