//
//  ChangeFeedTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins ``ChangeFeed``: what changed since an identity last looked, by others, with the
/// new values — and where to resume.
struct ChangeFeedTests {
    private static let titleID = "jSUCH"

    private func withFixture<T>(_ body: (URL, ActivityLog) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChangeFeedTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try #require(Bundle.module.url(
            forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
        ))
        let url = directory.appendingPathComponent("layout-vertical.pen")
        try FileManager.default.copyItem(at: source, to: url)
        return try await body(url, ActivityLog(home: directory.appendingPathComponent("home")))
    }

    /// Sets the title's width as `identity`.
    private static func setWidth(_ width: Int, of url: URL, as identity: String, log: ActivityLog) async throws {
        try await PenFileTransaction.run(at: url, identity: identity, log: log) { _, recorder in
            try recorder.apply(.setProperties(EditOperation.SetProperties(
                nodeID: titleID, properties: ["kind.width": .int(width)]
            )))
        }
    }

    // MARK: - First look

    @Test("A first look starts at the log's end, says so, and lists nothing")
    func firstLookStartsAtTheEnd() async throws {
        try await withFixture { url, log in
            try await Self.setWidth(120, of: url, as: "ben", log: log)
            let feed = ChangeFeed(file: url, identity: "claude", log: log)

            let report = try await feed.read()

            #expect(report.origin == .firstLook)
            #expect(report.changes.isEmpty)
            #expect(report.since == report.cursor)
            #expect(report.unlogged == nil)
        }
    }

    // MARK: - Others, not me

    @Test("Others' changes are listed with new values, and mine are not")
    func othersOnly() async throws {
        try await withFixture { url, log in
            let feed = ChangeFeed(file: url, identity: "claude", log: log)
            try await feed.save(feed.read())
            try await Self.setWidth(120, of: url, as: "claude", log: log)
            try await Self.setWidth(140, of: url, as: "ben", log: log)

            let report = try await feed.read()

            #expect(report.origin == .stored)
            #expect(report.changes.map(\.identity) == ["ben"])
            #expect(report.changes.first?.changes.first?.old == 120)
            #expect(report.changes.first?.changes.first?.new == 140)
        }
    }

    @Test("Every writer's changes are listed when asked, mine included")
    func everyone() async throws {
        try await withFixture { url, log in
            let feed = ChangeFeed(file: url, identity: "claude", writers: .everyone, log: log)
            try await feed.save(feed.read())
            try await Self.setWidth(120, of: url, as: "claude", log: log)
            try await Self.setWidth(140, of: url, as: "ben", log: log)

            #expect(try await feed.read().changes.map(\.identity) == ["claude", "ben"])
        }
    }

    // MARK: - Resuming

    @Test("A saved cursor resumes with no repeats, and an unsaved read does not move it")
    func resumesWithNoRepeats() async throws {
        try await withFixture { url, log in
            let feed = ChangeFeed(file: url, identity: "claude", log: log)
            try await feed.save(feed.read())
            try await Self.setWidth(120, of: url, as: "ben", log: log)

            let peeked = try await feed.read()
            let first = try await feed.read()
            try await feed.save(first)
            try await Self.setWidth(140, of: url, as: "ben", log: log)
            let second = try await feed.read()

            #expect(peeked == first)
            #expect(first.changes.flatMap(\.changes).map(\.new) == [120])
            #expect(second.changes.flatMap(\.changes).map(\.new) == [140])
            #expect(second.since == first.cursor)
        }
    }

    @Test("A given cursor overrides the stored one")
    func givenCursorOverrides() async throws {
        try await withFixture { url, log in
            let feed = ChangeFeed(file: url, identity: "claude", log: log)
            try await Self.setWidth(120, of: url, as: "ben", log: log)
            try await feed.save(feed.read())

            let report = try await feed.read(from: .cursor(.start))

            #expect(report.origin == .given)
            #expect(report.changes.map(\.identity) == ["ben"])
        }
    }

    // MARK: - Outside writes

    @Test("A file rewritten behind the log's back reports unlogged changes")
    func divergedFileReportsUnlogged() async throws {
        try await withFixture { url, log in
            try await Self.setWidth(120, of: url, as: "ben", log: log)
            let logged = try #require(ActivityReader(log: log).read().events.last)
            var document = try PenParser.parse(Data(contentsOf: url))
            document.children[0].common.name = "renamed outside"
            try PenParser.encodeForFile(document).write(to: url)

            let report = try await ChangeFeed(file: url, identity: "claude", log: log).read()

            let unlogged = try #require(report.unlogged)
            #expect(unlogged.since == logged.revision)
            #expect(unlogged.found == report.revision)
            #expect(unlogged.found != logged.revision)
        }
    }

    // MARK: - Waiting

    @Test("Waiting returns as soon as someone else writes")
    func waitReturnsOnForeignChange() async throws {
        try await withFixture { url, log in
            let feed = ChangeFeed(file: url, identity: "claude", log: log)
            try await feed.save(feed.read())

            async let report = feed.wait(timeout: .seconds(30))
            try await Task.sleep(for: .milliseconds(300))
            try await Self.setWidth(120, of: url, as: "claude", log: log)
            try await Self.setWidth(140, of: url, as: "ben", log: log)
            let started = ContinuousClock.now
            let result = try await report

            #expect(result.changes.map(\.identity) == ["ben"])
            #expect(ContinuousClock.now - started < .seconds(10))
        }
    }

    @Test("Waiting gives up at the timeout with nothing to report")
    func waitTimesOut() async throws {
        try await withFixture { url, log in
            let feed = ChangeFeed(file: url, identity: "claude", log: log)
            try await feed.save(feed.read())
            let started = ContinuousClock.now

            let result = try await feed.wait(timeout: .milliseconds(400))

            #expect(result.changes.isEmpty)
            #expect(result.unlogged == nil)
            #expect(ContinuousClock.now - started >= .milliseconds(400))
        }
    }

    @Test("Waiting returns on a write made outside woodcase")
    func waitReturnsOnOutsideWrite() async throws {
        try await withFixture { url, log in
            try await Self.setWidth(120, of: url, as: "ben", log: log)
            let feed = ChangeFeed(file: url, identity: "claude", log: log)
            try await feed.save(feed.read())

            async let report = feed.wait(timeout: .seconds(30))
            try await Task.sleep(for: .milliseconds(300))
            var document = try PenParser.parse(Data(contentsOf: url))
            document.children[0].common.name = "renamed outside"
            try PenParser.encodeForFile(document).write(to: url)

            #expect(try await report.unlogged != nil)
        }
    }

    // MARK: - Wire form

    @Test("A report's JSON carries cursor tokens, and round-trips")
    func reportJSON() async throws {
        try await withFixture { url, log in
            let feed = ChangeFeed(file: url, identity: "claude", log: log)
            let report = try await feed.read()

            let data = try JSONEncoder().encode(report)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["cursor"] as? String == report.cursor.token)
            #expect(object["since"] as? String == report.since.token)
            #expect(try JSONDecoder().decode(ChangeFeed.Report.self, from: data) == report)
        }
    }
}
