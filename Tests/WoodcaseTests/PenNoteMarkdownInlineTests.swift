//
//  PenNoteMarkdownInlineTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A note's markdown within a line: bold, italic, mentions, escapes, and everything
/// outside the subset showing as written.
struct PenNoteMarkdownInlineTests {
    private func parse(_ source: String) -> PenNoteMarkdown {
        PenNoteMarkdown(source, fontSize: 14)
    }

    /// The resolved style at each display offset, from the runs.
    private func segment(at offset: Int, in note: PenNoteMarkdown) -> PenTextSegment? {
        PenTextStyle().segments(of: note.displayText, runs: note.runs).first { $0.range.contains(offset) }
    }

    @Test("Double asterisks set bold and are removed")
    func bold() {
        let note = parse("a **bold** b")
        #expect(note.displayText == "a bold b")
        #expect(note.runs == [PenTextRun(start: 2, end: 6, fontWeight: PenNoteMarkdown.boldWeight)])
    }

    @Test("A single asterisk or underscore sets italic")
    func italic() {
        let note = parse("an *it* and _it_")
        #expect(note.displayText == "an it and it")
        #expect(note.runs == [PenTextRun(start: 3, end: 5, isItalic: true), PenTextRun(start: 10, end: 12, isItalic: true)])
    }

    @Test("Triple asterisks set bold italic")
    func boldItalic() {
        let note = parse("***both***")
        #expect(note.displayText == "both")
        let style = segment(at: 1, in: note)?.style
        #expect(style?.fontWeight == PenNoteMarkdown.boldWeight)
        #expect(style?.isItalic == true)
    }

    @Test("Italic nests inside bold")
    func nested() {
        let note = parse("**a *b* c**")
        #expect(note.displayText == "a b c")
        #expect(segment(at: 0, in: note)?.style.isItalic == false)
        #expect(segment(at: 2, in: note)?.style.isItalic == true)
        #expect(segment(at: 2, in: note)?.style.fontWeight == PenNoteMarkdown.boldWeight)
        #expect(segment(at: 4, in: note)?.style.fontWeight == PenNoteMarkdown.boldWeight)
    }

    @Test("Underscores inside a word, and unmatched or spaced delimiters, stay as written")
    func literalDelimiters() {
        for source in ["snake_case_name", "2 * 3 = 6", "**open", "a ** b ** c", "*"] {
            let note = parse(source)
            #expect(note.displayText == source, "\(source)")
            #expect(note.runs.isEmpty, "\(source)")
        }
    }

    @Test("A backslash escapes a delimiter and is removed")
    func escapes() {
        let note = parse(#"\*not italic\* and \@nobody"#)
        #expect(note.displayText == "*not italic* and @nobody")
        #expect(note.runs.isEmpty)
    }

    @Test("Links, code, tables, images and HTML show as their source")
    func unsupportedShowsAsSource() {
        for source in ["[link](http://x.y/a_b_c)", "`**not bold**` here", "| a | b |", "![img](a.png)", "<b>hi</b>"] {
            let note = parse(source)
            #expect(note.displayText == source, "\(source)")
            #expect(note.runs.isEmpty, "\(source)")
        }
    }

    @Test("An @mention is a run carrying the name, set semibold")
    func mention() {
        let note = parse("Ask @claude now")
        #expect(note.displayText == "Ask @claude now")
        #expect(note.runs == [PenTextRun(
            start: 4, end: 11, fontWeight: PenNoteMarkdown.mentionWeight, mention: "claude",
            inlinePadding: PenNoteMarkdown.mentionPadding * note.fontSize
        )])
        #expect(note.mentionedNames == ["claude"])
    }

    @Test("A mention's name takes letters, digits, dashes, underscores and inner dots")
    func mentionNames() {
        #expect(parse("@ben.").mentionedNames == ["ben"])
        #expect(parse("hi @codex-2_a.b, ok").mentionedNames == ["codex-2_a.b"])
        #expect(parse("@josé").mentionedNames == ["josé"])
        #expect(parse("(@ben)").mentionedNames == ["ben"])
        #expect(parse("@a @b @a").mentionedNames == ["a", "b"])
    }

    @Test("An address, a lone at sign and a mention in code are not mentions")
    func notMentions() {
        for source in ["mail a@b.com", "@ alone", "`@claude`", "@@"] {
            #expect(parse(source).mentionedNames.isEmpty, "\(source)")
        }
    }

    @Test("A mention in bold stays bold, and its segment carries the name")
    func mentionInBold() {
        let note = parse("**hey @ben**")
        #expect(note.displayText == "hey @ben")
        let segment = segment(at: 5, in: note)
        #expect(segment?.mention == "ben")
        #expect(segment?.style.fontWeight == PenNoteMarkdown.boldWeight)
    }

    @Test("Offsets count UTF-16 code units past an emoji")
    func utf16Offsets() {
        let note = parse("👍🏽 **ok**")
        #expect(note.displayText == "👍🏽 ok")
        #expect(note.runs.map(\.range) == [5 ..< 7])
    }
}
