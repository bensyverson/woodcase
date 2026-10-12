//
//  ReplyCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase reply` — adding a message to a thread. Ben's session 12 ruling: a reply
/// names the thread's first message, even when it was given a reply's id.
@Suite("woodcase reply threads under the first message")
struct ReplyCommandTests {
    @Test("A reply to a thread's reply still threads under the first message, with author and createdAt")
    func replyToReply() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("reply", fixture.file.path, "Cm02", "On it.", "--id", "CmR", "--as", "claude")

        #expect(run.status == 0, "reply refused: \(run.stderr)")
        #expect(run.stdoutLines.first == "reply  CmR  thread Cm01")

        let note = try #require(PenFileProbe(fixture.file).roots.first { $0.id == "CmR" })
        let metadata = try #require(note.common.metadata)
        #expect(metadata[woodcase: .type] == .string("comment"))
        #expect(metadata[woodcase: .replyTo] == .string("Cm01"))
        #expect(metadata[woodcase: .author] == .string("claude"))
        #expect(metadata[woodcase: .anchor] == nil)
        #expect(metadata[woodcase: .state] == nil)
        guard case let .string(createdAt)? = metadata[woodcase: .createdAt] else {
            Issue.record("no createdAt")
            return
        }
        #expect(PenComment.date(createdAt: createdAt) != nil)

        let listing = try fixture.run("comments", fixture.file.path, "--json")
        let report = try JSONDecoder().decode(PenNoteBoard.CommentsReport.self, from: Data(listing.stdout.utf8))
        #expect(report.threads.first?.messages.map(\.id) == ["Cm01", "Cm02", "Cm03", "CmR"])
    }

    @Test("A reply to something that is not a comment is refused with the threads there are")
    func notAComment() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let original = try Data(contentsOf: fixture.file)
        let run = try fixture.run("reply", fixture.file.path, "Nte01", "Hi", "--as", "ana")

        #expect(run.status == 2)
        #expect(run.stdout.isEmpty)
        #expect(run.stderr.contains("Nte01"), "stderr: \(run.stderr)")
        #expect(run.stderr.contains("Cm01, Cm04, Cm06"), "stderr: \(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == original)
    }

    @Test("A reply needs an author")
    func needsAuthor() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run(["reply", fixture.file.path, "Cm01", "Hi"], environment: ["WOODCASE_AS": ""])

        #expect(run.status == 2)
        #expect(run.stderr.contains("--as"), "stderr: \(run.stderr)")
    }

    @Test("A reply without text is refused")
    func needsText() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("reply", fixture.file.path, "Cm01", "--as", "ana")

        #expect(run.status == 2)
        #expect(run.stderr.contains("-F"), "stderr: \(run.stderr)")
    }
}
