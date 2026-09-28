//
//  MigrateAndNewLogTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `migrate` and `new` write through ``PenFileTransaction``, under the file's lock, and
/// leave a row in the activity log like every other write: `migrate` rewrites a file's
/// bytes without changing its model, `new` is the file's first event.
///
/// The log is read as raw lines here rather than through ``ActivityReader``, so these
/// assertions say what a tool tailing the file sees.
@Suite("migrate and new in the activity log")
struct MigrateAndNewLogTests {
    // MARK: - Helpers

    private typealias Row = [String: Any]

    /// Every row of the fixture's log, oldest first.
    private func rows(in fixture: CommandFixture) throws -> [Row] {
        guard FileManager.default.fileExists(atPath: fixture.activityLog.path) else { return [] }
        return try String(contentsOf: fixture.activityLog, encoding: .utf8)
            .split(separator: "\n")
            .map { try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? Row) }
    }

    /// The `op` of every row, oldest first.
    private func ops(in fixture: CommandFixture) throws -> [String] {
        try rows(in: fixture).compactMap { $0["op"] as? String }
    }

    /// Rewrites the file as compact JSON: the same document in bytes `migrate --force`
    /// will put back into canonical form.
    private func compact(_ url: URL) throws {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    // MARK: - migrate

    @Test("migrate records one migrate row, naming the writer and the file's revision")
    func migrateRecordsARow() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("migrate", fixture.file.path, "--as", "bob")

        #expect(run.status == 0, "\(run.stderr)")
        let row = try #require(try rows(in: fixture).last)
        #expect(row["op"] as? String == "migrate")
        #expect(row["identity"] as? String == "bob")
        #expect(row["inverse"] == nil || (row["inverse"] as? [Any])?.isEmpty == true)
        let tree = try fixture.run("tree", fixture.file.path)
        #expect(try tree.stdoutLines.first?.contains(#require(row["revision"] as? String).prefix(16)) == true)
    }

    @Test("A migrate without --as is recorded, unattributed")
    func migrateUnattributed() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        #expect(try fixture.run("migrate", fixture.file.path).status == 0)
        let row = try #require(try rows(in: fixture).last)
        #expect(row["op"] as? String == "migrate")
        #expect(row["identity"] as? String == ActivityEvent.unattributed)
    }

    @Test("A file already current, and a dry run, record nothing")
    func noWriteNoRow() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        #expect(try fixture.run("migrate", fixture.file.path, "--dry-run", "--as", "bob").status == 0)
        #expect(try ops(in: fixture).isEmpty)
        #expect(try fixture.run("migrate", fixture.file.path, "--as", "bob").status == 0)
        #expect(try fixture.run("migrate", fixture.file.path, "--as", "bob").status == 0)
        #expect(try ops(in: fixture) == ["migrate"])
    }

    @Test("A write after a migrate of a logged file carries no outside-write note")
    func writeAfterMigrateIsQuiet() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        #expect(try fixture.run("set", fixture.file.path, "Ttl01", "common.name=One", "--as", "ana").status == 0)
        try compact(fixture.file)

        #expect(try fixture.run("migrate", fixture.file.path, "--force", "--as", "bob").status == 0)
        let set = try fixture.run("set", fixture.file.path, "Ttl01", "common.name=Two", "--as", "ana")

        #expect(set.status == 0, "\(set.stderr)")
        #expect(try ops(in: fixture) == ["set", "migrate", "set"])
    }

    @Test("undo steps over somebody else's migrate to reach the writer's own edit")
    func undoStepsOverMigrate() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        #expect(try fixture.run("set", fixture.file.path, "Ttl01", "common.name=One", "--as", "ana").status == 0)
        try compact(fixture.file)
        #expect(try fixture.run("migrate", fixture.file.path, "--force", "--as", "bob").status == 0)
        #expect(try ops(in: fixture) == ["set", "migrate"])

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(undo.status == 0, "\(undo.stderr)")
        let get = try fixture.run("get", fixture.file.path, "Ttl01")
        #expect(!get.stdout.contains(#""name": "One""#))
    }

    // MARK: - new

    @Test("new records the file's first event, naming the writer and the revision it reports")
    func newRecordsFirstEvent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("design.pen")

        let run = try fixture.run("new", target.path, "--as", "ana", "--json")

        #expect(run.status == 0, "\(run.stderr)")
        let report = try #require(try JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? Row)
        let rows = try rows(in: fixture)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row["op"] as? String == "new")
        #expect(row["identity"] as? String == "ana")
        #expect(row["revision"] as? String == report["documentRevision"] as? String)
        #expect(row["file"] as? String == ActivityEvent.canonicalPath(for: target))
    }

    @Test("new --dry-run records nothing and creates nothing")
    func newDryRunRecordsNothing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("design.pen")
        #expect(try fixture.run("new", target.path, "--as", "ana", "--dry-run").status == 0)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(try ops(in: fixture).isEmpty)
    }

    @Test("undo reverses edits back to the new, and no further")
    func undoStopsAtNew() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("design.pen")
        #expect(try fixture.run("new", target.path, "--as", "ana").status == 0)
        let subtree = fixture.root.appendingPathComponent("subtree.json")
        try Data(#"{"type":"frame","name":"Hero","width":10,"height":10}"#.utf8).write(to: subtree)
        #expect(try fixture.run("add", target.path, "document", "-F", subtree.path, "--as", "ana").status == 0)
        #expect(try ops(in: fixture) == ["new", "add"])

        #expect(try fixture.run("undo", target.path, "--as", "ana").status == 0)
        let again = try fixture.run("undo", target.path, "--as", "ana")

        #expect(again.status == 1)
        #expect(again.stderr.contains("Nothing to undo"))
        #expect(FileManager.default.fileExists(atPath: target.path))
    }
}
