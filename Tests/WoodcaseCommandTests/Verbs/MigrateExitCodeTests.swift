//
//  MigrateExitCodeTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// The exit codes `woodcase migrate` promises, driven through the real binary, because
/// the status a shell sees is the subject.
///
/// A path that names nothing is a target failure (4), never the usage exit (2) with a
/// usage block: the invocation's shape was fine, the world was not. A path that names
/// the *wrong kind of thing* — a file that is not a .pen file — is the usage exit (2).
/// A file that exists but could not be rewritten is a target failure (4) too, the same
/// number every other verb returns for a .pen file it cannot read.
@Suite("woodcase migrate exit codes")
struct MigrateExitCodeTests {
    @Test("A path that names nothing is exit 4, with the path and a remedy")
    func missingPathIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let missing = fixture.root.appendingPathComponent("gone.pen")

        let run = try fixture.run("migrate", missing.path)

        #expect(run.status == 4)
        #expect(run.stderr.contains(missing.path))
        #expect(run.stderr.contains("no such file"))
        #expect(run.stderr.contains("ls \(fixture.root.path)"))
        #expect(!run.stderr.contains("USAGE"))
    }

    @Test("A directory is searched recursively, and the run succeeds")
    func directoryIsSearched() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let nested = fixture.root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let legacy = nested.appendingPathComponent("legacy.pen")
        try Data(Self.legacyJSON.utf8).write(to: legacy)

        let run = try fixture.run("migrate", fixture.root.path)

        #expect(run.status == 0)
        #expect(run.stdout.contains("migrated \(legacy.path)"))
        #expect(try String(contentsOf: legacy, encoding: .utf8).contains("\"version\": \"2.20\""))
    }

    @Test("A file that is not a .pen file is exit 2, and the message says what it wanted")
    func nonPenFileIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let notes = fixture.root.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notes)

        let run = try fixture.run("migrate", notes.path)

        #expect(run.status == 2)
        #expect(run.stderr.contains(notes.path))
        #expect(run.stderr.contains(".pen file"))
    }

    @Test("A .pen file that cannot be migrated is exit 4, and stderr names it")
    func unmigratableFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = fixture.root.appendingPathComponent("broken.pen")
        try Data("not json".utf8).write(to: broken)

        let run = try fixture.run("migrate", broken.path)

        #expect(run.status == 4)
        #expect(run.stderr.contains(broken.path))
    }

    @Test("--dry-run over a file it would change is still exit 0")
    func dryRunIsSuccess() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let legacy = fixture.root.appendingPathComponent("legacy.pen")
        try Data(Self.legacyJSON.utf8).write(to: legacy)

        let run = try fixture.run("migrate", legacy.path, "--dry-run")

        #expect(run.status == 0)
        #expect(run.stdout.contains("would migrate \(legacy.path)"))
        #expect(try String(contentsOf: legacy, encoding: .utf8) == Self.legacyJSON)
    }

    /// A 2.9 document, which the version gate migrates and `migrate` rewrites.
    private static let legacyJSON = """
    {
      "version": "2.9",
      "children": [
        {
          "type": "rectangle",
          "id": "r1",
          "width": 100,
          "height": 50,
          "stroke": { "fill": "#FF0000", "thickness": 2 }
        }
      ]
    }
    """
}
