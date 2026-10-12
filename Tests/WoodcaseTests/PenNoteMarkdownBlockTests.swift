//
//  PenNoteMarkdownBlockTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A note's markdown, line by line: headings, bullet, numbered and checklist items, and
/// the lines that stay as written.
struct PenNoteMarkdownBlockTests {
    private static let size: Double = 20

    private func parse(_ source: String) -> PenNoteMarkdown {
        PenNoteMarkdown(source, fontSize: Self.size)
    }

    @Test("Plain text displays as written, with no runs or indents")
    func plainText() {
        let note = parse("Hello world\nsecond line")
        #expect(note.displayText == "Hello world\nsecond line")
        #expect(note.runs.isEmpty)
        #expect(note.indents.isEmpty)
        #expect(note.checklistItems.isEmpty)
    }

    @Test("Blank lines and CRLF line ends are kept")
    func blankLinesAndCRLF() {
        #expect(parse("a\n\nb").displayText == "a\n\nb")
        #expect(parse("a\r\nb").displayText == "a\r\nb")
    }

    @Test("Each heading level is bold and scaled from the note's size")
    func headingLevels() throws {
        for (level, scale) in PenNoteMarkdown.headingScales.enumerated() {
            let hashes = String(repeating: "#", count: level + 1)
            let note = parse("\(hashes) Plan\nbody")
            #expect(note.displayText == "Plan\nbody")
            let run = try #require(note.runs.first)
            #expect(note.runs.count == 1)
            #expect(run.range == 0 ..< 4)
            #expect(abs((run.fontSize ?? 0) - scale * Self.size) < 1e-9)
            #expect(run.fontWeight == PenNoteMarkdown.boldWeight)
        }
    }

    @Test("A fourth-level heading, and a hash with no space, show as written")
    func unsupportedHeadings() {
        for source in ["#### Four", "#NoSpace"] {
            let note = parse(source)
            #expect(note.displayText == source)
            #expect(note.runs.isEmpty)
        }
    }

    @Test("Bullet items set a placeholder and a tab, record where the bullet is drawn, and hang")
    func bulletItems() {
        let note = parse("- one\n* two\n+ three")
        #expect(note.displayText == "\u{2003}\tone\n\u{2003}\ttwo\n\u{2003}\tthree")
        let indent = PenNoteMarkdown.listIndent * Self.size
        #expect(note.indents == [
            PenParagraphIndent(start: 0, end: 6, firstLineIndent: 0, headIndent: indent),
            PenParagraphIndent(start: 6, end: 12, firstLineIndent: 0, headIndent: indent),
            PenParagraphIndent(start: 12, end: 19, firstLineIndent: 0, headIndent: indent),
        ])
        #expect(note.bulletDisplayOffsets == [0, 6, 12])
    }

    @Test("Two leading spaces nest a list item one level in")
    func nestedBullet() {
        let note = parse("- a\n  - b")
        #expect(note.displayText == "\u{2003}\ta\n\u{2003}\tb")
        let indent = PenNoteMarkdown.listIndent * Self.size
        #expect(note.indents.last == PenParagraphIndent(start: 4, end: 7, firstLineIndent: indent, headIndent: 2 * indent))
    }

    @Test("Numbered items keep their number and hang after a tab")
    func numberedItems() {
        let note = parse("1. one\n2) two")
        #expect(note.displayText == "1.\tone\n2)\ttwo")
        #expect(note.indents.map(\.range) == [0 ..< 7, 7 ..< 13])
    }

    @Test("Checklist items set a placeholder for their box and record where their marker is")
    func checklistItems() {
        let note = parse("- [ ] todo\n- [x] done\n* [X] also")
        #expect(note.displayText == "\u{2003}\ttodo\n\u{2003}\tdone\n\u{2003}\talso")
        #expect(note.checklistItems == [
            PenNoteMarkdown.ChecklistItem(
                isChecked: false, markerSourceRange: 2 ..< 5, boxDisplayRange: 0 ..< 1, lineDisplayRange: 0 ..< 6
            ),
            PenNoteMarkdown.ChecklistItem(
                isChecked: true, markerSourceRange: 13 ..< 16, boxDisplayRange: 7 ..< 8, lineDisplayRange: 7 ..< 13
            ),
            PenNoteMarkdown.ChecklistItem(
                isChecked: true, markerSourceRange: 24 ..< 27, boxDisplayRange: 14 ..< 15, lineDisplayRange: 14 ..< 20
            ),
        ])
        #expect(note.indents.count == 3)
    }

    @Test("A dash with no space, and a rule, are not list items")
    func notListItems() {
        for source in ["-dash", "---", "1.5 litres"] {
            let note = parse(source)
            #expect(note.displayText == source)
            #expect(note.indents.isEmpty)
        }
    }

    @Test("Inline styling inside a list item and a heading is parsed")
    func inlineInsideBlocks() {
        let note = parse("# **Big** plan\n- [ ] ship *it*")
        #expect(note.displayText == "Big plan\n\u{2003}\tship it")
        #expect(note.runs.contains { $0.range == 0 ..< 8 && $0.fontSize != nil })
        #expect(note.runs.contains { $0.range == 0 ..< 3 && $0.fontWeight == PenNoteMarkdown.boldWeight })
        #expect(note.runs.contains { $0.range == 16 ..< 18 && $0.isItalic == true })
    }
}
