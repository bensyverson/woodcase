//
//  DifferentMajorCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A file declaring a different major version — 3.0 while this build models 2.x.
///
/// Per Ben's ruling (project/2026-09-26-pen-1.2.14-compatibility.md, ruling 3) it is
/// read-only: when it still decodes as a document, the read verbs work with a warning,
/// and every write verb refuses with an error naming the file, the two versions and
/// what to do instead. When it does not decode, every verb says why.
@Suite("A different-major .pen file")
struct DifferentMajorCommandTests {
    static let major = "3.0"

    // MARK: - Reads

    @Test("Read verbs work, with a warning naming the major", arguments: [
        ["tree"], ["get", "Canvas/Title"], ["find", "r => r.type === 'text'"],
    ])
    func readsWorkWithAWarning(_ arguments: [String]) throws {
        let fixture = try NewerMinorCommandTests.fixture(declaring: Self.major)
        var command = arguments
        command.insert(fixture.file.path, at: 1)

        let run = try fixture.run(command)

        #expect(run.status == 0, "\(run.stderr)")
        #expect(!run.stdout.isEmpty)
        #expect(run.stderr.contains("warning: [migration]"))
        #expect(run.stderr.contains(Self.major))
        #expect(run.stderr.contains("read-only"))
    }

    @Test("lint reports the warning as a finding")
    func lintReportsTheWarning() throws {
        let fixture = try NewerMinorCommandTests.fixture(declaring: Self.major)

        let run = try fixture.run("lint", fixture.file.path)

        #expect(run.stdout.contains("warning pipeline"))
        #expect(run.stdout.contains(Self.major))
    }

    // MARK: - Writes

    @Test("Every write verb refuses, naming the file, the versions and the read verbs", arguments: NewerMinorCommandTests.writes)
    func writesAreRefused(_ write: NewerMinorCommandTests.WriteCase) throws {
        let fixture = try NewerMinorCommandTests.fixture(declaring: Self.major)
        try write.writeBody(into: fixture)
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(write.commandLine(on: fixture.file))

        #expect(run.status == ExitCode.targetFailure.rawValue, "\(run.stdout)\(run.stderr)")
        #expect(run.stderr.contains("Cannot write \(fixture.file.path)"))
        #expect(run.stderr.contains(Self.major))
        #expect(run.stderr.contains("read-only"))
        #expect(run.stderr.contains("woodcase tree"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("undo refuses too")
    func undoIsRefused() throws {
        let fixture = try NewerMinorCommandTests.fixture(declaring: Self.major)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(run.status == ExitCode.targetFailure.rawValue, "\(run.stderr)")
        #expect(run.stderr.contains("read-only"))
    }

    @Test("A dry run is refused too: the write it rehearses would be")
    func dryRunIsRefused() throws {
        let fixture = try NewerMinorCommandTests.fixture(declaring: Self.major)

        let run = try fixture.run("set", fixture.file.path, "Canvas/Title", "kind.content=Hi", "--dry-run")

        #expect(run.status == ExitCode.targetFailure.rawValue, "\(run.stderr)")
        #expect(run.stderr.contains("read-only"))
    }

    @Test("migrate refuses it and reports the failure")
    func migrateRefuses() throws {
        let fixture = try NewerMinorCommandTests.fixture(declaring: Self.major)
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("migrate", fixture.file.path, "--force")

        #expect(run.status == ExitCode.targetFailure.rawValue, "\(run.stderr)")
        #expect(run.stderr.contains("read-only"))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - Not a document

    @Test("A different major that does not decode names the conflicting key")
    func undecodableMajorNamesTheKey() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = fixture.root.appendingPathComponent("future.pen")
        try Data(#"""
        {"version": "3.0", "children": [{"id": "Box01", "type": "frame", "width": {"min": 10}, "height": 10}]}
        """#.utf8).write(to: broken)

        let run = try fixture.run("tree", broken.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("Cannot read \(broken.path)"))
        #expect(run.stderr.contains("different major version"))
        #expect(run.stderr.contains("children[0].width"))
        #expect(run.stderr.contains("update Woodcase"))
    }
}
