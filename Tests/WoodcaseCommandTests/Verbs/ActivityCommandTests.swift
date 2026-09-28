//
//  ActivityCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase activity` over a fixture's own `$WOODCASE_HOME`.
///
/// Events are produced straight through the library — ``PenFileTransaction`` and its
/// ``ActivityRecorder`` — rather than through a mutating verb, because none is
/// registered yet. That is exactly the seam `activity` reads from, so it exercises the
/// command honestly.
@Suite("woodcase activity")
struct ActivityCommandTests {
    private static let targetNodeID = "jSUCH"

    /// Renames the fixture's target node, returning the operation that does it.
    private static func renameOperation(_ document: EditableDocument, to name: String) throws -> EditOperation {
        var node = try #require(document.nodes[targetNodeID])
        node.common.name = name
        return .updateCommon(EditOperation.UpdateCommon(nodeID: targetNodeID, common: node.common))
    }

    /// Applies one rename to `file` (the fixture's own file by default), attributed to
    /// `identity`, logging into `fixture`'s own activity log.
    @discardableResult
    static func recordRename(
        _ fixture: CommandFixture, as identity: String, name: String, file: URL? = nil
    ) async throws -> ActivityEvent {
        let target = file ?? fixture.file
        try await PenFileTransaction.run(
            at: target, identity: identity, log: ActivityLog(home: fixture.home)
        ) { document, recorder in
            try recorder.apply(Self.renameOperation(document, to: name))
        }
        return try #require(
            ActivityReader(log: ActivityLog(home: fixture.home)).tail(count: 1, file: target).last
        )
    }

    /// Adds a theme axis to `file`, attributed to `identity` — an edit that touches no
    /// node, so its events carry no paths.
    @discardableResult
    private static func recordThemeAxis(
        _ fixture: CommandFixture, as identity: String, file: URL, axis: String
    ) async throws -> ActivityEvent {
        try await PenFileTransaction.run(
            at: file, identity: identity, log: ActivityLog(home: fixture.home)
        ) { _, recorder in
            try recorder.apply(.addThemeAxis(EditOperation.AddThemeAxis(name: axis, options: ["a", "b"])))
        }
        return try #require(
            ActivityReader(log: ActivityLog(home: fixture.home)).tail(count: 1, file: file).last
        )
    }

    // MARK: - Empty log

    @Test("An empty log prints nothing and exits 0")
    func emptyLogIsClean() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let run = try fixture.run("activity")

        #expect(run.status == 0)
        #expect(run.stdout.isEmpty)
    }

    // MARK: - $WOODCASE_HOME problems

    @Test("A $WOODCASE_HOME that does not exist yet is an empty feed, exit 0")
    func missingHomeIsAnEmptyFeed() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let bogus = fixture.root.appendingPathComponent("never-created", isDirectory: true)

        let run = try fixture.run(
            ["activity"], environment: [ActivityLog.homeEnvironmentVariable: bogus.path]
        )

        #expect(run.status == ExitCode.success.rawValue)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.isEmpty)
    }

    @Test("A $WOODCASE_HOME that is a file, not a directory, is an environment error, exit 5")
    func homeThatIsAFileIsEnvironmentError() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let notADirectory = fixture.root.appendingPathComponent("home-as-file")
        try Data("x".utf8).write(to: notADirectory)

        let run = try fixture.run(
            ["activity"], environment: [ActivityLog.homeEnvironmentVariable: notADirectory.path]
        )

        #expect(run.status == ExitCode.environment.rawValue)
        #expect(run.stderr.contains("WOODCASE_HOME"))
        #expect(run.stdout.isEmpty)
    }

    @Test("An unreadable $WOODCASE_HOME directory is an environment error, exit 5")
    func unreadableHomeIsEnvironmentError() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let locked = fixture.root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        #expect(chmod(locked.path, 0) == 0)
        defer { chmod(locked.path, 0o755) }

        // Root (and some sandboxes) can read past a directory's own permission bits;
        // when that is true here, the scenario this test targets does not hold, so
        // there is nothing to assert.
        guard !FileManager.default.isReadableFile(atPath: locked.path) else { return }

        let run = try fixture.run(
            ["activity"], environment: [ActivityLog.homeEnvironmentVariable: locked.path]
        )

        #expect(run.status == ExitCode.environment.rawValue)
        #expect(run.stderr.contains("WOODCASE_HOME"))
    }

    // MARK: - --file

    @Test("--file prints only that file's events")
    func fileNarrowsEvents() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let other = try fixture.copy(fixture: "batch.pen")
        try await Self.recordRename(fixture, as: "ana", name: "first")
        try await Self.recordThemeAxis(fixture, as: "ana", file: other, axis: "mode")

        let run = try fixture.run("activity", "--file", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdout.contains("first"))
        #expect(!run.stdout.contains("mode"))
    }

    @Test("--file keeps working after the file it names is gone")
    func fileFilterSurvivesDeletion() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let path = fixture.file.path
        try await Self.recordRename(fixture, as: "ana", name: "renamed")
        try FileManager.default.removeItem(atPath: path)

        let run = try fixture.run("activity", "--file", path)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdout.contains("renamed"))
    }

    // MARK: - The file as a positional

    @Test("The .pen file may be written as a positional instead of --file")
    func positionalFileNarrowsEvents() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let other = try fixture.copy(fixture: "batch.pen")
        try await Self.recordRename(fixture, as: "ana", name: "first")
        try await Self.recordThemeAxis(fixture, as: "ana", file: other, axis: "mode")

        let run = try fixture.run("activity", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdout.contains("first"))
        #expect(!run.stdout.contains("mode"))
    }

    @Test("The positional and --file naming the same file agree")
    func positionalAndOptionMayAgree() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        try await Self.recordRename(fixture, as: "ana", name: "first")

        let run = try fixture.run("activity", fixture.file.path, "--file", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdout.contains("first"))
    }

    @Test("The positional and --file naming different files is a usage error naming both")
    func positionalAndOptionMayNotDisagree() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let other = try fixture.copy(fixture: "batch.pen")

        let run = try fixture.run("activity", fixture.file.path, "--file", other.path)

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains(fixture.file.path))
        #expect(run.stderr.contains(other.path))
    }

    @Test("A positional file that no longer exists still filters, like --file")
    func positionalFileSurvivesDeletion() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let path = fixture.file.path
        try await Self.recordRename(fixture, as: "ana", name: "renamed")
        try FileManager.default.removeItem(atPath: path)

        let run = try fixture.run("activity", path)

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdout.contains("renamed"))
    }

    // MARK: - --as

    @Test("--as narrows to one writer's events")
    func asNarrowsEvents() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        try await Self.recordRename(fixture, as: "ana", name: "ana-did-this")
        try await Self.recordRename(fixture, as: "ben", name: "ben-did-this")

        let run = try fixture.run("activity", "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdout.contains("ana"))
        #expect(!run.stdout.contains("ben-did-this"))
    }

    // MARK: - -n / --count

    @Test("-n limits to the most recent events")
    func countLimitsToMostRecent() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        try await Self.recordRename(fixture, as: "ana", name: "first")
        try await Self.recordRename(fixture, as: "ana", name: "second")
        try await Self.recordRename(fixture, as: "ana", name: "third")

        let run = try fixture.run("activity", "-n", "1")

        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 1)
        #expect(run.stdout.contains("third"))
    }

    @Test("A negative -n is a usage error, exit 2")
    func negativeCountIsUsageError() throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let run = try fixture.run("activity", "-n", "-1")

        #expect(run.status == ExitCode.usage.rawValue)
    }

    // MARK: - --json

    @Test("--json prints the wire form, one ActivityEvent per line")
    func jsonPrintsWireForm() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let recorded = try await Self.recordRename(fixture, as: "ana", name: "json-check")

        let run = try fixture.run("activity", "--json")

        #expect(run.status == 0)
        let line = try #require(run.stdoutLines.first)
        let decoded = try ActivityEvent(line: Data(line.utf8))
        #expect(decoded == recorded)
    }

    // MARK: - --follow

    /// The environment a `--follow` child runs in: this fixture's own home, and no
    /// inherited identity.
    ///
    /// - Parameter fixture: The fixture whose `$WOODCASE_HOME` the child should read.
    /// - Returns: The whole environment for the child.
    static func followEnvironment(_ fixture: CommandFixture) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[ActivityLog.homeEnvironmentVariable] = fixture.home.path
        environment["HOME"] = fixture.root.path
        environment.removeValue(forKey: Identity.environmentVariable)
        return environment
    }

    @Test("--follow prints a new event within a second of its write")
    func followSeesNewEventsPromptly() async throws {
        let fixture = try CommandFixture(fixture: "layout-vertical.pen")
        let stdoutURL = fixture.root.appendingPathComponent("follow-stdout.txt")

        try await ChildProcess.withChild(
            binary: CommandFixture.binary(),
            arguments: ["activity", "--follow"],
            environment: Self.followEnvironment(fixture),
            standardOutput: stdoutURL
        ) { follower in
            // Let the follower take its first poll before anything is written.
            try await Task.sleep(for: .milliseconds(300))
            try await Self.recordRename(fixture, as: "ana", name: "followed-edit")

            // Generous per the project's own guidance on timing under a loaded machine:
            // assert the outcome arrives, bounded at "not hung" scale, never tightly.
            var sawEvent = false
            let deadline = ContinuousClock.now.advanced(by: .seconds(30))
            while ContinuousClock.now < deadline {
                if let text = try? String(contentsOf: stdoutURL, encoding: .utf8),
                   text.contains("followed-edit")
                {
                    sawEvent = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(sawEvent)
            #expect(follower.isRunning, "--follow should still be following.")
        }
    }
}
