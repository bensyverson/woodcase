//
//  ResolveCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase resolve` and `--reopen` — ending a conversation, and taking it up again.
/// Only a comment thread has a state (Ben, 2026-10-11), and it lives on the first message.
@Suite("woodcase resolve sets a thread's state")
struct ResolveCommandTests {
    private func state(of id: String, in fixture: CommandFixture) throws -> AnyCodable? {
        try #require(PenFileProbe(fixture.file).roots.first { $0.id == id }).common.metadata?[woodcase: .state]
    }

    @Test("resolve sets the first message's state, given a reply; --reopen sets it back")
    func resolveAndReopen() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let resolve = try fixture.run("resolve", fixture.file.path, "Cm03", "--as", "ana")

        #expect(resolve.status == 0, "resolve refused: \(resolve.stderr)")
        #expect(resolve.stdoutLines.first == "resolved  Cm01")
        #expect(try state(of: "Cm01", in: fixture) == .string("resolved"))
        #expect(try state(of: "Cm03", in: fixture) == nil)

        let reopen = try fixture.run("resolve", fixture.file.path, "Cm01", "--reopen", "--as", "ana")
        #expect(reopen.status == 0, "reopen refused: \(reopen.stderr)")
        #expect(reopen.stdoutLines.first == "open  Cm01")
        #expect(try state(of: "Cm01", in: fixture) == .string("open"))
    }

    @Test("Resolving a resolved thread writes nothing and says so")
    func alreadyResolved() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let original = try Data(contentsOf: fixture.file)
        let run = try fixture.run("resolve", fixture.file.path, "Cm04", "--as", "ana")

        #expect(run.status == 0, "resolve refused: \(run.stderr)")
        #expect(run.stdout.contains("already resolved"), "stdout: \(run.stdout)")
        #expect(try Data(contentsOf: fixture.file) == original)
    }

    @Test("Resolving something that is not a comment is refused with the threads there are")
    func notAComment() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("resolve", fixture.file.path, "Zz999", "--as", "ana")

        #expect(run.status == 2)
        #expect(run.stderr.contains("Cm01, Cm04, Cm06"), "stderr: \(run.stderr)")
    }

    @Test("A stale --rev on the first message is a conflict")
    func staleRevision() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        let run = try fixture.run("resolve", fixture.file.path, "Cm01", "--rev", "0000000000000000", "--as", "ana")

        #expect(run.status == 3, "stderr: \(run.stderr)")
    }

    @Test("The resolve is undoable like any write")
    func undo() throws {
        let fixture = try CommandFixture(fixture: "notes-comments-prompts.pen")
        _ = try fixture.run("resolve", fixture.file.path, "Cm01", "--as", "ana")
        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")

        #expect(undo.status == 0, "undo refused: \(undo.stderr)")
        #expect(try state(of: "Cm01", in: fixture) == .string("open"))
    }
}
