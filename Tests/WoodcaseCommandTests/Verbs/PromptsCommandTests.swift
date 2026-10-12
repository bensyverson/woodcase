//
//  PromptsCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase prompts` — the Run queue: each prompt's run state and who requested it, so
/// an agent can claim queued work. Penumbra's notes design rev 2, decision 14.
@Suite("woodcase prompts lists the Run queue")
struct PromptsCommandTests {
    @Test("prompts lists every prompt by state and requestedBy")
    func listsPrompts() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("prompts", fixture.file.path)

        #expect(run.status == 0, "prompts refused: \(run.stderr)")
        let lines = run.stdoutLines
        try #require(lines.count == 6)
        #expect(lines[0].hasSuffix("4 prompts"))
        #expect(lines[1].split(separator: " ") == ["state", "requestedBy", "model", "text", "id"])
        #expect(lines[2].split(separator: " ") == ["queued", "ben", "claude-opus", "Make", "the", "button", "primary", "Pr01"])
        #expect(lines[3].hasPrefix("running ") && lines[3].contains(" ana ") && lines[3].hasSuffix("Pr02"))
        #expect(lines[4].hasPrefix("done ") && lines[4].hasSuffix("Pr03"))
        #expect(lines[5].split(separator: " ") == ["-", "-", "-", "Draft", "a", "dark", "theme", "Pr04"])
    }

    @Test("--state queued lists the work there is to claim")
    func queued() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("prompts", fixture.file.path, "--state", "queued")

        #expect(run.status == 0, "prompts refused: \(run.stderr)")
        try #require(run.stdoutLines.count == 3)
        #expect(run.stdoutLines[2].hasSuffix("Pr01"))
    }

    @Test("--requested-by keeps one requester's prompts")
    func requestedBy() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("prompts", fixture.file.path, "--requested-by", "ben")

        #expect(run.stdoutLines.dropFirst(2).map { $0.split(separator: " ").last } == ["Pr01", "Pr03"])
    }

    @Test("A misspelled --state is refused with the run states")
    func misspelledState() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("prompts", fixture.file.path, "--state", "queud")

        #expect(run.status == 2)
        for choice in ["queued", "running", "done", "all"] {
            #expect(run.stderr.contains(choice), "stderr: \(run.stderr)")
        }
    }

    @Test("A misspelled --requested-by is refused with the one meant")
    func misspelledRequester() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("prompts", fixture.file.path, "--requested-by", "bne")

        #expect(run.status == 2)
        #expect(run.stderr.contains("did you mean `--requested-by ben`"), "stderr: \(run.stderr)")
    }

    @Test("Nothing queued is a clean negative")
    func nothingQueued() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let claim = try fixture.run(
            "set", fixture.file.path, "Pr01", "common.metadata.woodcase.state=running", "--as", "claude"
        )
        #expect(claim.status == 0, "claim refused: \(claim.stderr)")

        let run = try fixture.run("prompts", fixture.file.path, "--state", "queued")
        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
    }

    @Test("--json carries each prompt's rev, to claim it with --rev")
    func json() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("prompts", fixture.file.path, "--json")

        let report = try JSONDecoder().decode(PenNoteBoard.PromptsReport.self, from: Data(run.stdout.utf8))
        try #require(report.prompts.map(\.state) == ["queued", "running", "done", nil])
        #expect(report.prompts[0].requestedBy == "ben")
        let rev = try #require(report.prompts.first?.rev)

        let claim = try fixture.run(
            "set", fixture.file.path, "Pr01", "common.metadata.woodcase.state=running", "--rev", rev, "--as", "claude"
        )
        #expect(claim.status == 0, "claim refused: \(claim.stderr)")
    }
}
