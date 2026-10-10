//
//  ViewInvariantTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase

/// Attributed reads leave the write history's invariants exactly as they were: undo
/// still undoes, the log's lineage still explains the file, and change attribution
/// still sees only writes. Views live in `views.jsonl` precisely so that these hold.
struct ViewInvariantTests {
    /// Every attributed read verb, against the fixture's title.
    private func readEverything(_ fixture: CommandFixture, as identity: String) throws {
        for arguments in [
            ["tree", fixture.file.path],
            ["get", fixture.file.path, "Canvas/Title"],
            ["find", fixture.file.path, "r => r.type === 'text'"],
        ] {
            let run = try fixture.run(arguments + ["--as", identity])
            #expect(run.status == 0, "\(arguments): \(run.stderr)")
        }
        #expect(try !ViewReader(log: ViewLog(home: fixture.home)).read().events.isEmpty)
    }

    private func set(_ fixture: CommandFixture, _ content: String, as identity: String) throws {
        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=\(content)", "--as", identity)
        #expect(run.status == 0, "\(run.stderr)")
    }

    @Test("set, then an attributed read by the same identity, then undo still undoes")
    func undoStillUndoes() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try fixture.run("get", fixture.file.path, "Canvas/Title").stdout
        try set(fixture, "Changed", as: "claude")
        try readEverything(fixture, as: "claude")

        let undo = try fixture.run("undo", fixture.file.path, "--as", "claude")

        #expect(undo.status == 0, "\(undo.stderr)")
        let after = try fixture.run("get", fixture.file.path, "Canvas/Title").stdout
        #expect(after.split(separator: "\n").dropFirst() == before.split(separator: "\n").dropFirst())
    }

    @Test("An attributed read by someone else does not block an undo either")
    func othersReadsDoNotBlockUndo() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try set(fixture, "Changed", as: "claude")
        try readEverything(fixture, as: "ana")

        let undo = try fixture.run("undo", fixture.file.path, "--as", "claude")
        #expect(undo.status == 0, "\(undo.stderr)")
    }

    @Test("The log's lineage stays current after attributed reads")
    func lineageStaysCurrent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try set(fixture, "Changed", as: "claude")
        try readEverything(fixture, as: "claude")

        let header = try #require(try fixture.run("tree", fixture.file.path, "--depth", "0").stdoutLines.first)
        let revision = String(header.split(separator: " ")[1])
        let lineage = try LogLineage.read(
            fixture.file, at: revision, from: ActivityLog(home: fixture.home, origin: .environmentOverride)
        )
        #expect(lineage.newest?.identity == "claude")
        #expect(!lineage.isDiverged)
        if case .current = lineage {} else { Issue.record("lineage is \(lineage), not current") }
    }

    @Test("Change attribution sees only the write, however many reads follow it")
    func attributionSeesOnlyWrites() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try set(fixture, "Changed", as: "claude")
        let written = try ActivityReader(log: ActivityLog(home: fixture.home)).read().events
        try readEverything(fixture, as: "claude")
        try readEverything(fixture, as: "ana")

        let rows = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(rows.events == written)
        #expect(rows.skippedLines == 0)

        var matcher = ChangeMatcher()
        for row in rows.events {
            matcher.logged(row)
        }
        let match = matcher.fileChanged(path: ActivityEvent.canonicalPath(for: fixture.file), at: Date())
        #expect(match?.events.map(\.identity) == written.map(\.identity))
    }
}
