//
//  ProjectLocalLogTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Where the binary puts its activity log when nothing overrides it: `.woodcase/` at the
/// repository root above the .pen file, or beside the file when there is no repository.
///
/// Every other command test runs with `$WOODCASE_HOME` pointed inside its fixture, which
/// is the override and therefore says nothing about the default. These runs clear it —
/// an empty value is ignored, which is exactly the "no override" case — so the resolver
/// is what decides.
@Suite("Project-local activity log")
struct ProjectLocalLogTests {
    /// The environment for a run with no `$WOODCASE_HOME` override.
    private static let noOverride = [ActivityLog.homeEnvironmentVariable: ""]

    /// Marks `root` as a repository root the way a checkout does.
    private func makeCheckout(at root: URL) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    /// Moves the fixture's .pen file into a subdirectory of the fixture root.
    private func move(_ fixture: CommandFixture, into name: String) throws -> URL {
        let directory = fixture.root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let moved = directory.appendingPathComponent(fixture.file.lastPathComponent)
        try FileManager.default.moveItem(at: fixture.file, to: moved)
        return moved
    }

    /// The log file `.woodcase` holds inside `directory`.
    private func logFile(in directory: URL) -> URL {
        directory
            .appendingPathComponent(ActivityLog.directoryName, isDirectory: true)
            .appendingPathComponent(ActivityLog.fileName)
    }

    // MARK: - Inside a repository

    @Test("A write inside a repository logs at the repository root and ignores .woodcase")
    func writeInRepositoryLogsAtTheRoot() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try makeCheckout(at: fixture.root)
        let file = try move(fixture, into: "designs")

        let run = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"],
            environment: Self.noOverride
        )

        #expect(run.status == 0)
        let log = logFile(in: fixture.root)
        #expect(FileManager.default.fileExists(atPath: log.path))
        #expect(!FileManager.default.fileExists(atPath: logFile(in: file.deletingLastPathComponent()).path))

        let ignore = try String(
            contentsOf: fixture.root.appendingPathComponent(".gitignore"), encoding: .utf8
        )
        #expect(ignore.contains(ActivityLog.ignorePattern))
    }

    @Test("Touching .gitignore is announced on stderr, naming the entry and the file")
    func gitignoreEditIsAnnounced() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try makeCheckout(at: fixture.root)
        let file = try move(fixture, into: "designs")

        let run = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"],
            environment: Self.noOverride
        )

        #expect(run.status == 0)
        #expect(run.stderr.contains(ActivityLog.ignorePattern))
        #expect(run.stderr.contains(fixture.root.appendingPathComponent(".gitignore").path))
        // The write's own answer is the answer; the side effect is a message.
        #expect(!run.stdout.contains(".gitignore"))
    }

    @Test("A second write says nothing, because it changed nothing")
    func gitignoreEditIsAnnouncedOnlyWhenItHappens() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try makeCheckout(at: fixture.root)
        let file = try move(fixture, into: "designs")
        _ = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=One", "--as", "ana"],
            environment: Self.noOverride
        )

        let second = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=Two", "--as", "ana"],
            environment: Self.noOverride
        )

        #expect(second.status == 0)
        #expect(!second.stderr.contains(".gitignore"))
    }

    @Test("activity with no --file reads the working directory's log")
    func activityReadsTheWorkingDirectorysLog() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try makeCheckout(at: fixture.root)
        let file = try move(fixture, into: "designs")
        _ = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"],
            environment: Self.noOverride
        )

        let run = try fixture.run(["activity"], environment: Self.noOverride)

        #expect(run.status == 0)
        #expect(run.stdout.contains("ana"))
        #expect(run.stdout.contains("set"))
    }

    // MARK: - Outside a repository

    @Test("A file outside any repository logs beside itself and writes no .gitignore")
    func writeOutsideRepositoryLogsBesideTheFile() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try move(fixture, into: "designs")

        let run = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"],
            environment: Self.noOverride
        )

        #expect(run.status == 0)
        #expect(FileManager.default.fileExists(
            atPath: logFile(in: file.deletingLastPathComponent()).path
        ))
        #expect(!FileManager.default.fileExists(atPath: logFile(in: fixture.root).path))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent(".gitignore").path
        ))
    }

    @Test("activity --file reads that file's own log, not the working directory's")
    func activityFileReadsTheFilesOwnLog() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try move(fixture, into: "designs")
        _ = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"],
            environment: Self.noOverride
        )

        let bare = try fixture.run(["activity"], environment: Self.noOverride)
        #expect(bare.status == 0)
        #expect(bare.stdout.isEmpty)

        let narrowed = try fixture.run(["activity", "--file", file.path], environment: Self.noOverride)
        #expect(narrowed.status == 0)
        #expect(narrowed.stdout.contains("ana"))
    }

    // MARK: - undo

    @Test("undo replays from the file's own log, not the working directory's")
    func undoReadsTheFilesOwnLog() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let file = try move(fixture, into: "designs")
        _ = try fixture.run(
            ["set", file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana"],
            environment: Self.noOverride
        )

        let run = try fixture.run(["undo", file.path, "--as", "ana"], environment: Self.noOverride)

        #expect(run.status == 0)
        #expect(try PenFileProbe(file).node("Canvas/Title")?.textContent != "Hello")
    }
}
