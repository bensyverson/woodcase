//
//  CommandFixtureTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// Proves the harness the verb suites are built on: it finds the binary, copies a
/// fixture, and reports stdout, stderr and the exit status faithfully.
@Suite("Driving the built binary")
struct CommandFixtureTests {
    @Test("A fixture is copied into a temporary directory of its own")
    func copiesTheFixture() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        #expect(FileManager.default.fileExists(atPath: fixture.file.path))
        #expect(fixture.file.path.hasPrefix(fixture.root.path))
        #expect(fixture.activityLog.path.hasPrefix(fixture.home.path))
    }

    @Test("A verb that works exits 0 and says what it did on stdout")
    func successfulVerb() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("migrate", "--dry-run", "--force", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdout.contains("would migrate \(fixture.file.path)"))
        #expect(run.stdoutLines.count == 2)
    }

    @Test("A verb that does not exist is a usage error, exit 2")
    func unknownVerbIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("bogus", fixture.file.path)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(!run.stderr.isEmpty)
    }

    @Test("An unknown flag is a usage error, exit 2")
    func unknownFlagIsUsage() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("migrate", "--nonsense", fixture.file.path)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("nonsense"))
    }

    @Test("Help needs no file and exits 0")
    func helpIsFree() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("--help")

        #expect(run.status == 0)
        #expect(run.stdout.contains("USAGE"))
    }

    @Test("A run's activity log is the fixture's own, not the developer's")
    func homeIsRedirected() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(["migrate", "--dry-run", fixture.file.path])

        #expect(run.status == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
    }
}
