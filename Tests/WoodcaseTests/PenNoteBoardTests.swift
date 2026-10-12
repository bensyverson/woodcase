//
//  PenNoteBoardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The notes, comment threads and prompts a document holds, read the way `woodcase
/// notes`, `comments` and `prompts` list them. Penumbra's notes design rev 2, decisions
/// 1, 7, 8 and 14: every plain note is a post-it, comments are notes one per message,
/// and prompts queue work in the file.
struct PenNoteBoardTests {
    private func board() throws -> PenNoteBoard {
        let url = try #require(Bundle.module.url(
            forResource: "notes-comments-prompts", withExtension: "pen", subdirectory: "Fixtures"
        ))
        return try PenNoteBoard(document: EditableDocument(from: PenParser.parse(contentsOf: url)))
    }

    // MARK: - Notes

    @Test("Notes are the plain notes, not comments or prompts, in document order")
    func notesAreNotComments() throws {
        let notes = try board().notes
        #expect(notes.map(\.id) == ["Nte01", "Nte02", "Nte03"])
    }

    @Test("A note carries its author, tint, settled size and first line, from either spelling")
    func noteColumns() throws {
        let notes = try board().notes
        try #require(notes.count == 3)
        let plan = try #require(notes.first)
        #expect(plan.author == "ana")
        #expect(plan.tint == "#A5D6A7")
        #expect(plan.size == PenSize(width: 200, height: 160))
        #expect(plan.firstLine == "Plan")
        #expect(plan.content == "# Plan\n- [ ] Ship the **comments** verb")

        let old = notes[1]
        #expect(old.author == "claude")
        #expect(old.tint == "#90CAF9")
        #expect(old.firstLine == "Old-style post-it")

        let empty = notes[2]
        #expect(empty.author == nil)
        #expect(empty.tint == nil)
        #expect(empty.firstLine == "")
        #expect(empty.size == PenSize(width: 200, height: 200))
    }

    @Test("Notes filter by author")
    func notesByAuthor() throws {
        let notes = try board().notes(PenNoteBoard.NoteQuery(author: "claude"))
        #expect(notes.map(\.id) == ["Nte02"])
    }

    // MARK: - Threads

    @Test("Comment messages group into threads: the first message, then its replies in order")
    func threadsGroupReplies() throws {
        let threads = try board().threads
        try #require(threads.map(\.id) == ["Cm01", "Cm04", "Cm06", "Gone1"])
        #expect(threads[0].messages.map(\.id) == ["Cm01", "Cm02", "Cm03"])
        #expect(threads[0].messages.map(\.author) == ["ana", "claude", "ben"])
        #expect(threads[1].messages.map(\.id) == ["Cm04", "Cm05"])
    }

    @Test("A thread carries its anchor and its state")
    func threadAnchorAndState() throws {
        let threads = try board().threads
        try #require(threads.count == 4)
        #expect(threads[0].anchor == PenCommentThread.Anchor(node: "Btn01", x: 12, y: 4))
        #expect(threads[0].state == .open)
        #expect(threads[1].state == .resolved)
        #expect(threads[1].anchor?.node == "Card1")
    }

    @Test("A reply whose first message is gone is its own thread, flagged")
    func orphanReply() throws {
        let orphan = try #require(board().threads.last)
        #expect(orphan.isMissingFirstMessage)
        #expect(orphan.anchor == nil)
        #expect(orphan.messages.map(\.id) == ["Cm07"])
    }

    @Test("A thread mentions everyone any of its messages mentions")
    func threadMentions() throws {
        let threads = try board().threads
        try #require(threads.count == 4)
        #expect(threads[0].mentions == ["claude", "ana"])
        #expect(threads[0].messages[0].mentions == ["claude"])
        #expect(threads[2].mentions.isEmpty)
    }

    @Test("--mentions keeps open threads unless a state is named")
    func mentionsDefaultsToOpen() throws {
        let board = try board()
        #expect(board.threads(PenNoteBoard.CommentQuery(mentions: "claude")).map(\.id) == ["Cm01"])
        #expect(
            board.threads(PenNoteBoard.CommentQuery(mentions: "claude", state: .all)).map(\.id) == ["Cm01", "Cm04"]
        )
        #expect(
            board.threads(PenNoteBoard.CommentQuery(mentions: "claude", state: .resolved)).map(\.id) == ["Cm04"]
        )
    }

    @Test("With no filter every thread is listed; --state and --author narrow it")
    func stateAndAuthorFilters() throws {
        let board = try board()
        #expect(board.threads(PenNoteBoard.CommentQuery()).count == 4)
        #expect(board.threads(PenNoteBoard.CommentQuery(state: .open)).map(\.id) == ["Cm01", "Cm06"])
        // A thread is an author's when any message in it is theirs.
        #expect(board.threads(PenNoteBoard.CommentQuery(author: "claude")).map(\.id) == ["Cm01", "Cm04"])
    }

    // MARK: - Prompts

    @Test("Prompts list with their run state, who requested the run, and the model")
    func promptColumns() throws {
        let prompts = try board().prompts
        try #require(prompts.map(\.id) == ["Pr01", "Pr02", "Pr03", "Pr04"])
        #expect(prompts.map(\.state) == ["queued", "running", "done", nil])
        #expect(prompts.map(\.requestedBy) == ["ben", "ana", "ben", nil])
        #expect(prompts[0].model == "claude-opus")
        #expect(prompts[0].firstLine == "Make the button primary")
    }

    @Test("Prompts filter by state and by who requested the run")
    func promptFilters() throws {
        let board = try board()
        #expect(board.prompts(PenNoteBoard.PromptQuery(state: .queued)).map(\.id) == ["Pr01"])
        #expect(board.prompts(PenNoteBoard.PromptQuery(requestedBy: "ben")).map(\.id) == ["Pr01", "Pr03"])
        #expect(board.prompts(PenNoteBoard.PromptQuery(state: .all)).count == 4)
    }

    // MARK: - Identities

    @Test("The identities a file names: authors, mentions and requesters, sorted")
    func identities() throws {
        #expect(try board().identities == ["ana", "ben", "claude"])
    }

    @Test("A known identity passes, with or without its @")
    func knownIdentity() throws {
        let board = try board()
        #expect(try board.identity("claude", for: "--mentions") == .known("claude"))
        #expect(try board.identity("@claude", for: "--mentions") == .known("claude"))
    }

    @Test("A misspelled identity is refused, naming the one meant and the valid choices")
    func misspelledIdentity() throws {
        let board = try board()
        #expect(throws: PenNoteBoard.FilterError.misspelledIdentity(
            option: "--mentions", value: "cluade", suggestion: "claude", known: ["ana", "ben", "claude"]
        )) {
            try board.identity("cluade", for: "--mentions")
        }
        #expect(throws: PenNoteBoard.FilterError.self) {
            try board.identity("Claude", for: "--author")
        }
    }

    @Test("Swapped letters count as one slip, so the suggestion is the name meant")
    func transposition() throws {
        #expect(throws: PenNoteBoard.FilterError.misspelledIdentity(
            option: "--requested-by", value: "bne", suggestion: "ben", known: ["ana", "ben", "claude"]
        )) {
            try board().identity("bne", for: "--requested-by")
        }
    }

    @Test("A name nothing in the file is close to is unknown, not refused")
    func unknownIdentity() throws {
        #expect(try board().identity("zebulon", for: "--mentions") == .unknown("zebulon", known: ["ana", "ben", "claude"]))
    }

    @Test("A misspelling's message names the flag, the choices and the remedy")
    func misspellingMessage() {
        let error = PenNoteBoard.FilterError.misspelledIdentity(
            option: "--mentions", value: "cluade", suggestion: "claude", known: ["ana", "claude"]
        )
        #expect(error.message.contains("--mentions cluade"))
        #expect(error.message.contains("did you mean `--mentions claude`"))
        #expect(error.message.contains("ana, claude"))
    }
}
