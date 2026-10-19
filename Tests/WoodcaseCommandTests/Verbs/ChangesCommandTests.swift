//
//  ChangesCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase changes`: what others changed since my last look, driven through the binary.
@Suite("woodcase changes")
struct ChangesCommandTests {
    private static let target = "jSUCH"

    /// Sets the target's width through the binary, as `identity`.
    private static func setWidth(_ width: Int, in fixture: CommandFixture, as identity: String) throws {
        let run = try fixture.run("set", fixture.file.path, target, "kind.width=\(width)", "--as", identity)
        #expect(run.status == 0, "set exited \(run.status): \(run.stderr)")
    }

    private static func changes(_ fixture: CommandFixture, _ arguments: String...) throws -> CommandRun {
        try fixture.run(["changes", fixture.file.path] + arguments)
    }

    // MARK: - Identity

    @Test("With no identity it refuses, exit 2, and names --as")
    func requiresIdentity() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")

        let run = try Self.changes(fixture)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("--as"))
        #expect(run.stderr.contains("WOODCASE_AS"))
    }

    // MARK: - First look and resuming

    @Test("A first look says so, prints the cursor last, and lists nothing")
    func firstLook() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        try Self.setWidth(120, in: fixture, as: "ben")

        let run = try Self.changes(fixture, "--as", "claude")

        #expect(run.status == 0)
        #expect(run.stdout.contains("first look"))
        #expect(!run.stdout.contains("kind.width"))
        #expect(run.stdoutLines.last?.hasPrefix("cursor ") == true)
    }

    @Test("Others' changes are listed with old and new values, and mine are not")
    func listsOthersWithNewValues() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        _ = try Self.changes(fixture, "--as", "claude")
        try Self.setWidth(120, in: fixture, as: "claude")
        try Self.setWidth(140, in: fixture, as: "ben")

        let run = try Self.changes(fixture, "--as", "claude")

        #expect(run.status == 0)
        let rows = run.stdoutLines.filter { $0.contains("kind.width") }
        #expect(rows.count == 1)
        #expect(rows.first?.contains("ben") == true)
        #expect(rows.first?.contains("layout-vertical/child-1  kind.width: 120 → 140") == true)
        #expect(run.stdoutLines.last?.hasPrefix("cursor ") == true)
    }

    @Test("The cursor resumes with no repeats")
    func resumesWithNoRepeats() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        _ = try Self.changes(fixture, "--as", "claude")
        try Self.setWidth(140, in: fixture, as: "ben")
        _ = try Self.changes(fixture, "--as", "claude")
        try Self.setWidth(160, in: fixture, as: "ben")

        let run = try Self.changes(fixture, "--as", "claude")
        let again = try Self.changes(fixture, "--as", "claude")

        let rows = run.stdoutLines.filter { $0.contains("kind.width") }
        #expect(rows.count == 1)
        #expect(rows.first?.contains("140 → 160") == true)
        #expect(!again.stdout.contains("kind.width"))
        #expect(again.stdout.contains("no changes by others"))
    }

    @Test("--peek leaves the cursor where it was")
    func peekDoesNotAdvance() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        _ = try Self.changes(fixture, "--as", "claude")
        try Self.setWidth(140, in: fixture, as: "ben")

        let peeked = try Self.changes(fixture, "--as", "claude", "--peek")
        let read = try Self.changes(fixture, "--as", "claude")

        #expect(peeked.stdout.contains("kind.width: 100 → 140"))
        #expect(read.stdout.contains("kind.width: 100 → 140"))
    }

    @Test("--since reads from a cursor given back, overriding the stored one")
    func sinceOverrides() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        try Self.setWidth(140, in: fixture, as: "ben")
        _ = try Self.changes(fixture, "--as", "claude")

        let run = try Self.changes(fixture, "--as", "claude", "--since", ActivityCursor.start.token, "--peek")

        #expect(run.status == 0)
        #expect(run.stdout.contains("kind.width: 100 → 140"))
    }

    @Test("A --since that is not a cursor is a usage error, exit 2")
    func badSince() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")

        let run = try Self.changes(fixture, "--as", "claude", "--since", "yesterday")

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("cursor"))
    }

    @Test("--mine lists my own rows too")
    func mineIncludesOwnRows() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        _ = try Self.changes(fixture, "--as", "claude")
        try Self.setWidth(120, in: fixture, as: "claude")

        let run = try Self.changes(fixture, "--as", "claude", "--mine")

        #expect(run.stdoutLines.contains { $0.contains("claude") && $0.contains("kind.width: 100 → 120") })
    }

    // MARK: - JSON

    @Test("--json prints the report: file, revision, cursor, since, unlogged and changes")
    func json() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        _ = try Self.changes(fixture, "--as", "claude")
        try Self.setWidth(140, in: fixture, as: "ben")

        let run = try Self.changes(fixture, "--as", "claude", "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(ChangeFeed.Report.self, from: Data(run.stdout.utf8))
        #expect(report.changes.map(\.identity) == ["ben"])
        #expect(report.changes.first?.changes.first?.new == 140)
        #expect(report.unlogged == nil)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any])
        #expect(Set(object.keys).isSuperset(of: ["file", "revision", "cursor", "since", "unlogged", "changes"]))
    }

    // MARK: - Waiting

    @Test("--wait returns on the first foreign change")
    func waitReturnsOnForeignChange() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        _ = try Self.changes(fixture, "--as", "claude")

        let live = try fixture.runInBackground(["changes", fixture.file.path, "--as", "claude", "--wait", "60"])
        Thread.sleep(forTimeInterval: 0.5)
        try Self.setWidth(140, in: fixture, as: "ben")
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while live.process.isRunning, ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        live.stop()

        let stdout = (try? String(contentsOf: live.stdoutURL, encoding: .utf8)) ?? ""
        #expect(live.process.terminationStatus == 0)
        #expect(stdout.contains("kind.width: 100 → 140"))
    }

    @Test("--wait gives up at the timeout: exit 3, the cursor still printed")
    func waitTimesOut() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        _ = try Self.changes(fixture, "--as", "claude")

        let run = try Self.changes(fixture, "--as", "claude", "--wait", "1")

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("1s"))
        #expect(run.stdoutLines.last?.hasPrefix("cursor ") == true)
    }

    // MARK: - Outside writes and failures

    @Test("A file changed outside woodcase reports unlogged changes")
    func divergedFileReportsUnlogged() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen", editedOutsideWoodcase: true)
        try Self.setWidth(140, in: fixture, as: "ben")
        _ = try Self.changes(fixture, "--as", "claude")
        var document = try PenParser.parse(Data(contentsOf: fixture.file))
        document.children[0].common.name = "renamed outside"
        try PenParser.encodeForFile(document).write(to: fixture.file)

        let run = try Self.changes(fixture, "--as", "claude")
        let json = try Self.changes(fixture, "--as", "claude", "--json", "--peek")

        #expect(run.status == 0)
        #expect(run.stdout.contains("changed outside woodcase since rev"))
        #expect(run.stdout.contains("woodcase tree"))
        let report = try JSONDecoder().decode(ChangeFeed.Report.self, from: Data(json.stdout.utf8))
        #expect(report.unlogged != nil)
    }

    @Test("A file that does not exist exits 4")
    func missingFile() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")

        let run = try fixture.run(
            "changes", fixture.root.appendingPathComponent("nope.pen").path, "--as", "claude"
        )

        #expect(run.status == ExitCode.targetFailure.rawValue)
    }
}
