//
//  DocumentLinterNoteStateTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `note-state`: a notice on a plain note that still keeps a `state`. Only comments are
/// open or resolved, and a prompt's run state is its own (Ben's ruling, 2026-10-11), so a
/// note's state is not drawn; the notice says so rather than `woodcase migrate` dropping
/// it, since the value is the author's.
@MainActor
struct DocumentLinterNoteStateTests {
    private func findings(_ children: String) throws -> [LintFinding] {
        let document = try EditableDocument(from: PenParser.parse(#"{"version": "2.20", "children": ["# + children + "]}"))
        return try DocumentLinter.findings(in: document).filter { $0.check == .noteState }
    }

    @Test("A plain note's state, in either spelling, gets one notice naming its value")
    func plainNoteState() throws {
        let found = try findings("""
        {"id": "N1", "type": "note", "content": "a", "metadata": {"type": "woodcase", "woodcase": {"state": "resolved"}}},
        {"id": "N2", "type": "note", "content": "b", "metadata": {"type": "postit", "state": "open"}},
        {"id": "N3", "type": "note", "content": "c", "metadata": {"type": "woodcase", "woodcase": {"type": "postit", "state": "open"}}}
        """)
        #expect(found.map(\.nodeID) == ["N1", "N2", "N3"])
        #expect(found.allSatisfy { $0.severity == .notice })
        #expect(found.first?.message.contains("resolved") == true)
        #expect(found.first?.message.contains("comment") == true)
    }

    @Test("A comment's and a prompt's state, and a note without one, are not flagged")
    func commentsAndPrompts() throws {
        let found = try findings("""
        {"id": "C1", "type": "note", "content": "a", "metadata": {"woodcase": {"type": "comment", "state": "resolved"}}},
        {"id": "P1", "type": "prompt", "content": "b", "metadata": {"woodcase": {"state": "queued"}}},
        {"id": "N1", "type": "note", "content": "c", "metadata": {"woodcase": {"author": "ben"}}},
        {"id": "F1", "type": "frame", "metadata": {"type": "board", "state": "resolved"}}
        """)
        #expect(found.isEmpty)
    }

    @Test("The check is a notice")
    func checkIsANotice() {
        #expect(LintCheck.noteState.rawValue == "note-state")
        #expect(LintCheck.noteState.severity == .notice)
    }
}
