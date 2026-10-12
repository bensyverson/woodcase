//
//  PenNoteChecklistTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Toggling a note's checklist item rewrites only its `[ ]`/`[x]` in the source.
struct PenNoteChecklistTests {
    private static let source = "Plan\n- [ ] todo\n- [X] done"

    @Test("Toggling an open item ticks it, a done one clears it, and another note's item changes nothing")
    func toggles() throws {
        let note = PenNoteMarkdown(Self.source)
        try #require(note.checklistItems.count == 2)
        #expect(note.toggling(note.checklistItems[0]) == "Plan\n- [x] todo\n- [X] done")
        #expect(note.toggling(note.checklistItems[1]) == "Plan\n- [ ] todo\n- [ ] done")
        let foreign = PenNoteMarkdown.ChecklistItem(
            isChecked: false, markerSourceRange: 0 ..< 3, boxDisplayRange: 0 ..< 1, lineDisplayRange: 0 ..< 4
        )
        #expect(note.toggling(foreign) == Self.source)
    }

    @Test("A toggled source parses with the box flipped")
    func toggledParses() throws {
        let note = PenNoteMarkdown(Self.source)
        try #require(note.checklistItems.count == 2)
        let toggled = PenNoteMarkdown(note.toggling(note.checklistItems[0]))
        #expect(toggled.checklistItems.map(\.isChecked) == [true, true])
        #expect(toggled.displayText == "Plan\n\u{2003}\ttodo\n\u{2003}\tdone")
    }

    @Test("A display offset on an item's box or words finds the item; elsewhere none")
    func itemAtOffset() throws {
        let note = PenNoteMarkdown(Self.source)
        let first = try #require(note.checklistItems.first)
        #expect(note.checklistItem(atDisplayOffset: first.boxDisplayRange.lowerBound) == first)
        #expect(note.checklistItem(atDisplayOffset: first.lineDisplayRange.upperBound - 1) == first)
        #expect(note.checklistItem(atDisplayOffset: 1) == nil)
    }
}
