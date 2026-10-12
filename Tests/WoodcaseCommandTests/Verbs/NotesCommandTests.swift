//
//  NotesCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase notes` — the post-its in a file: plain notes, never comments or prompts.
/// A note has no state and no kind (Ben, 2026-10-11), so the listing has neither.
@Suite("woodcase notes lists post-its")
struct NotesCommandTests {
    @Test("notes lists each plain note's author, tint, settled size and first line")
    func listsNotes() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("notes", fixture.file.path)

        #expect(run.status == 0, "notes refused: \(run.stderr)")
        let lines = run.stdoutLines
        try #require(lines.count == 5)
        #expect(lines[0].hasPrefix("rev "))
        #expect(lines[0].hasSuffix("3 notes"))
        #expect(lines[1].split(separator: " ") == ["author", "tint", "size", "text", "id"])
        #expect(lines[2].split(separator: " ") == ["ana", "#A5D6A7", "200×160", "Plan", "Nte01"])
        #expect(lines[3].split(separator: " ") == ["claude", "#90CAF9", "200×200", "Old-style", "post-it", "Nte02"])
        #expect(lines[4].split(separator: " ") == ["-", "-", "200×200", "Nte03"])
    }

    @Test("--author keeps one author's notes")
    func author() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("notes", fixture.file.path, "--author", "ana")

        #expect(run.status == 0, "notes refused: \(run.stderr)")
        try #require(run.stdoutLines.count == 3)
        #expect(run.stdoutLines[2].hasSuffix("Nte01"))
    }

    @Test("notes takes no --state: a note has none")
    func noState() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let help = try fixture.run("notes", "--help")

        #expect(help.status == 0, "notes --help refused: \(help.stderr)")
        #expect(help.stdout.contains("--author"))
        #expect(!help.stdout.contains("--state"), "help: \(help.stdout)")
    }

    @Test("--json carries each note with its content and rev")
    func json() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("notes", fixture.file.path, "--json")

        #expect(run.status == 0, "notes refused: \(run.stderr)")
        let report = try JSONDecoder().decode(PenNoteBoard.NotesReport.self, from: Data(run.stdout.utf8))
        try #require(report.notes.map(\.id) == ["Nte01", "Nte02", "Nte03"])
        #expect(report.notes[0].content == "# Plan\n- [ ] Ship the **comments** verb")
        #expect(report.notes[0].size == PenSize(width: 200, height: 160))
        #expect(report.notes.allSatisfy { !$0.rev.isEmpty })
    }
}
