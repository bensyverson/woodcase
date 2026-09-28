//
//  UndoTransactionTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Drives the built binary's `undo` over commands that log more than one event.
///
/// This is the 2026-09-07 ruling in test form: one step of `undo` is one *transaction*,
/// so a `cp --times 3` — six events — goes back with one `undo` rather than with `-n 6`,
/// and `-n` counts commands. ``UndoCommandTests`` pins the single-event shape, whose
/// output this change leaves exactly as it was; `--event` is the older per-row form,
/// kept for a reader who means one row.
struct UndoTransactionTests {
    // MARK: - Helpers

    private static let fixtureName = "batch.pen"

    /// Rewrites the fixture copy in the canonical on-disk form, so that "byte for byte
    /// as it was" is a meaningful assertion about a hand-written fixture.
    private static func canonicalize(_ url: URL) throws {
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: url))).write(to: url)
    }

    /// Every event in the fixture's own log, oldest first.
    private static func events(in fixture: CommandFixture) throws -> [ActivityEvent] {
        try ActivityReader(log: ActivityLog(home: fixture.home)).read().events
    }

    /// Copies `Canvas/Cards/First` three times, which logs six events in one command.
    private static func copyThreeTimes(in fixture: CommandFixture) throws -> CommandRun {
        try fixture.run(
            "cp", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards",
            "common.name=Card {n}", "--times", "3", "--as", "ana"
        )
    }

    // MARK: - One command, one undo

    @Test("A six-event copy is reversed by one undo, and the file is byte for byte back")
    func oneCommandIsOneUndo() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        #expect(try Self.copyThreeTimes(in: fixture).status == 0)
        #expect(try Self.events(in: fixture).count == 6)
        #expect(try Set(Self.events(in: fixture).compactMap(\.batch)).count == 1)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(run.status == 0)
        // One row per event still — the log's rows are what was reversed — but one
        // command's worth of them, and one revision line.
        #expect(run.stdoutLines.count == 7)
        #expect(run.stdoutLines.last?.hasPrefix("revision ") == true)
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    @Test("-n 2 reverses two commands, not two events")
    func countReversesTwoCommands() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        #expect(try Self.copyThreeTimes(in: fixture).status == 0)
        let second = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Changed", "--as", "ana"
        )
        #expect(second.status == 0)

        let run = try fixture.run("undo", fixture.file.path, "-n", "2", "--as", "ana")
        #expect(run.status == 0)
        // The `set` (one event) and the copy (six), newest first, then the revision.
        #expect(run.stdoutLines.count == 8)
        #expect(run.stdoutLines[0].hasPrefix("set  ana  "))
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - The row, when the row is what you mean

    @Test("--event reverses one logged row of the command, leaving the rest")
    func eventFlagReversesOneRow() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        #expect(try Self.copyThreeTimes(in: fixture).status == 0)

        let run = try fixture.run("undo", fixture.file.path, "--event", "--as", "ana")
        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 2)
        // The newest event of the copy is the third copy's rename.
        #expect(run.stdoutLines[0].hasPrefix("set  ana  "))
        #expect(try Data(contentsOf: fixture.file) != before)

        // Five rows of that one command are left, and a plain undo takes them together.
        let rest = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(rest.status == 0)
        #expect(rest.stdoutLines.count == 6)
        #expect(try Data(contentsOf: fixture.file) == before)
    }

    // MARK: - A batch is a transaction too

    @Test("A batch of three lines goes back in one undo")
    func aBatchIsOneUndo() throws {
        let fixture = try CommandFixture(fixture: Self.fixtureName)
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        let batch = """
        {"op":"set","target":"Canvas/Title","props":{"kind.content":"One"}}
        {"op":"set","target":"Canvas/Cards/First","props":{"common.name":"Two"}}
        {"op":"set","target":"Canvas/Cards/Second","props":{"common.name":"Three"}}
        """
        let applied = try fixture.run(
            ["apply", fixture.file.path, "-F", "-", "--as", "ana"], stdin: Data(batch.utf8)
        )
        #expect(applied.status == 0)

        let run = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(run.status == 0)
        #expect(run.stdoutLines.count == 4)
        #expect(try Data(contentsOf: fixture.file) == before)
    }
}
