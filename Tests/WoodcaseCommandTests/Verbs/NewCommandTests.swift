//
//  NewCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase new` writes the minimum a `.pen` file needs, so there is something for
/// `add` to grow and `tree` to read.
@Suite("woodcase new")
struct NewCommandTests {
    @Test("Writes the minimum document: the current version and empty children")
    func writesTheMinimumDocument() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("design.pen")

        let run = try fixture.run("new", target.path)

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
        let probe = try PenFileProbe(target)
        #expect(probe.document.version == PenDocument.currentFormatVersion)
        #expect(probe.roots.isEmpty)
        #expect(probe.document.themes == nil)
        #expect(probe.document.variables == nil)
        #expect(probe.document.imports == nil)
    }

    @Test("tree reads what new created, and add can extend it")
    func treeAndAddWorkOnANewFile() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("design.pen")
        #expect(try fixture.run("new", target.path).status == 0)

        let treeRun = try fixture.run("tree", target.path)
        #expect(treeRun.status == 0)

        let subtree = fixture.root.appendingPathComponent("subtree.json")
        try #"{"type":"frame","name":"Hero","width":10,"height":10}"#
            .write(to: subtree, atomically: true, encoding: .utf8)
        let addRun = try fixture.run("add", target.path, "document", "-F", subtree.path)

        #expect(addRun.status == 0)
        #expect(try PenFileProbe(target).root(named: "Hero") != nil)
    }

    @Test("Refuses to overwrite an existing file, naming `tree` as the read")
    func refusesToOverwrite() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("new", fixture.file.path)

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains(fixture.file.path))
        #expect(run.stderr.contains("already exists"))
        #expect(run.stderr.contains("woodcase tree"))
    }

    @Test("Does not create a missing parent directory, and names it")
    func doesNotCreateParentDirectories() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("nowhere/design.pen")

        let run = try fixture.run("new", target.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains(target.deletingLastPathComponent().path))
    }

    @Test("--json answers with the path and the document revision")
    func jsonOutput() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("design.pen")

        let run = try fixture.run("new", target.path, "--json")

        #expect(run.status == 0)
        let report = try JSONDecoder().decode(NewFileReport.self, from: Data(run.stdout.utf8))
        #expect(report.path == target.path)
        #expect(report.documentRevision?.count == 16)
    }

    /// `new` writes through `PenFileTransaction.create`, so --as names the file's first
    /// event in the activity log.
    @Test("--as names the file's first event in the log")
    func asNamesTheFirstEvent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let target = fixture.root.appendingPathComponent("design.pen")

        let run = try fixture.run("new", target.path, "--as", "ana")

        #expect(run.status == 0)
        let page = try ActivityReader(log: ActivityLog(home: fixture.home)).read()
        #expect(page.events.map(\.op) == [.new])
        #expect(page.events.first?.identity == "ana")
    }
}
