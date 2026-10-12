//
//  CommentsCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase comments` — the comment threads in a file, so an agent can find the ones
/// that mention it. Penumbra's notes design rev 2, decisions 7 and 8.
@Suite("woodcase comments lists threads")
struct CommentsCommandTests {
    /// The ids a listing's rows end in, header lines skipped.
    private func ids(_ run: CommandRun) -> [String] {
        run.stdoutLines.dropFirst(2).compactMap { $0.split(separator: " ").last.map(String.init) }
    }

    @Test("comments lists every thread with its replies, anchor and state")
    func listsThreads() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comments", fixture.file.path)

        #expect(run.status == 0, "comments refused: \(run.stderr)")
        let lines = run.stdoutLines
        try #require(lines.count > 2)
        #expect(lines[0].hasPrefix("rev "))
        #expect(lines[0].hasSuffix("4 threads  7 messages"))
        #expect(lines[1].split(separator: " ", omittingEmptySubsequences: true)
            == ["state", "anchor", "author", "mentions", "text", "id"])
        #expect(ids(run) == ["Cm01", "Cm02", "Cm03", "Cm04", "Cm05", "Cm06", "Cm07"])

        let first = try #require(lines.first { $0.hasSuffix("Cm01") })
        #expect(first.hasPrefix("open "))
        #expect(first.contains("Btn01 @12,4"))
        #expect(first.contains("@claude"))
        #expect(first.contains("Should this be 44pt tall, @claude?"))
        let reply = try #require(lines.first { $0.hasSuffix("Cm02") })
        #expect(reply.hasPrefix("  reply "))
        let resolved = try #require(lines.first { $0.hasSuffix("Cm04") })
        #expect(resolved.hasPrefix("resolved "))
        let orphan = try #require(lines.first { $0.hasSuffix("Cm07") })
        #expect(orphan.contains("⚠ no first message Gone1"), "orphan reads \(orphan)")
    }

    @Test("--mentions claude --state open keeps the open threads that mention claude")
    func mentionsAndState() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comments", fixture.file.path, "--mentions", "claude", "--state", "open")

        #expect(run.status == 0, "comments refused: \(run.stderr)")
        #expect(ids(run) == ["Cm01", "Cm02", "Cm03"])
    }

    @Test("--mentions alone keeps open threads; --state all brings back the resolved")
    func mentionsDefaultsToOpen() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let open = try fixture.run("comments", fixture.file.path, "--mentions", "@claude")
        let all = try fixture.run("comments", fixture.file.path, "--mentions", "claude", "--state", "all")

        #expect(ids(open) == ["Cm01", "Cm02", "Cm03"])
        #expect(ids(all) == ["Cm01", "Cm02", "Cm03", "Cm04", "Cm05"])
    }

    @Test("--author keeps the threads someone wrote in")
    func author() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comments", fixture.file.path, "--author", "ben", "--state", "resolved")

        #expect(ids(run) == ["Cm04", "Cm05"])
    }

    @Test("A misspelled --state is refused with the valid choices")
    func misspelledState() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comments", fixture.file.path, "--state", "opne")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        for choice in ["open", "resolved", "all"] {
            #expect(run.stderr.contains(choice), "stderr: \(run.stderr)")
        }
    }

    @Test("A misspelled --mentions is refused with the valid choices and the one meant")
    func misspelledMentions() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comments", fixture.file.path, "--mentions", "cluade")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("did you mean `--mentions claude`"), "stderr: \(run.stderr)")
        #expect(run.stderr.contains("ana, ben, claude"), "stderr: \(run.stderr)")
    }

    @Test("No thread matching is a clean negative: nothing printed, exit 1, and who the file knows")
    func noMatch() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comments", fixture.file.path, "--mentions", "zebulon")

        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("ana, ben, claude"), "stderr: \(run.stderr)")
    }

    @Test("--json carries each thread with its messages, mentions and per-node revs")
    func json() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("comments", fixture.file.path, "--mentions", "claude", "--json")

        #expect(run.status == 0, "comments refused: \(run.stderr)")
        let report = try JSONDecoder().decode(PenNoteBoard.CommentsReport.self, from: Data(run.stdout.utf8))
        #expect(report.threads.map(\.id) == ["Cm01"])
        let thread = try #require(report.threads.first)
        #expect(thread.state == "open")
        #expect(thread.anchor == PenCommentThread.Anchor(node: "Btn01", x: 12, y: 4))
        try #require(thread.messages.map(\.id) == ["Cm01", "Cm02", "Cm03"])
        #expect(thread.messages.allSatisfy { !$0.rev.isEmpty })
        #expect(thread.messages[1].replyTo == "Cm01")
        #expect(!report.revision.isEmpty)
    }

    @Test("A file with no comments is a clean negative")
    func noComments() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("comments", fixture.file.path)

        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
    }
}
