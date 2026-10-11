//
//  PenNoteTextTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A note's text: its style from `metadata.woodcase`, its markdown parsed at that size,
/// and the layout a renderer sets it with.
struct PenNoteTextTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    /// A note node parsed from JSON.
    private func note(_ json: String) throws -> PenNode {
        let document = try PenParser.parse(#"{"version": "2.17", "children": ["# + json + "]}")
        return try #require(document.children.first)
    }

    @Test("A note's style comes from metadata.woodcase, then its own keys, then the defaults; a text has none")
    func styleFromMetadata() throws {
        let node = try note("""
        {"id": "N1", "type": "note", "content": "hi", "fontWeight": "700", "letterSpacing": 2,
         "metadata": {"type": "woodcase", "woodcase": {"fontSize": 20, "fontFamily": "Inter",
           "lineHeight": 1.4, "fontStyle": "italic", "textAlign": "center", "fontWeight": 300}}}
        """)
        let style = try #require(node.noteTextStyle)
        #expect(style.fontSize == 20)
        #expect(style.fontFamily == "Inter")
        #expect(style.lineHeight == 1.4)
        #expect(style.isItalic)
        #expect(style.textAlign == .center)
        #expect(style.fontWeight == 300)
        #expect(style.letterSpacing == 2)
        #expect(style.textAlignVertical == .top)
        let text = try note(##"{"id": "T1", "type": "text", "content": "# hi"}"##)
        #expect(text.noteTextStyle == nil)
        #expect(text.noteMarkdown == nil)
    }

    @Test("A note with no style keys takes the text defaults; a wrong-typed value is skipped")
    func styleDefaults() throws {
        let node = try note("""
        {"id": "N1", "type": "note", "content": "hi", "fontSize": 18,
         "metadata": {"type": "woodcase", "woodcase": {"fontSize": "big", "textAlign": "sideways"}}}
        """)
        let style = try #require(node.noteTextStyle)
        #expect(style.fontSize == 18)
        #expect(style.textAlign == .left)
        #expect(style.fontFamily == PenTextStyle.defaultFontFamily)
    }

    @Test("A note's markdown is parsed at its metadata font size")
    func markdownAtNoteSize() throws {
        let node = try note("""
        {"id": "N1", "type": "note", "content": "# Head\\n@claude",
         "metadata": {"type": "woodcase", "woodcase": {"fontSize": 20}}}
        """)
        let markdown = try #require(node.noteMarkdown)
        #expect(markdown.displayText == "Head\n@claude")
        #expect(markdown.fontSize == 20)
        #expect(markdown.runs.first?.fontSize == 30)
        #expect(markdown.mentionedNames == ["claude"])
    }

    @Test("A comment is a note, and parses the same way")
    func commentParses() throws {
        let node = try note("""
        {"id": "C1", "type": "note", "content": "**ok** @ben",
         "metadata": {"type": "woodcase", "woodcase": {"type": "comment"}}}
        """)
        #expect(node.noteMarkdown?.displayText == "ok @ben")
    }

    @Test("A note's layout sets the display text, runs and indents in the inset box")
    func noteLayout() throws {
        let node = try note("""
        {"id": "N1", "type": "note", "content": "**Plan**\\n- one", "width": 200, "height": 200,
         "metadata": {"type": "woodcase", "woodcase": {"fontSize": 14}}}
        """)
        let markdown = try #require(node.noteMarkdown)
        let layout = try #require(PenTextLayout(note: node, size: CGSize(width: 200, height: 240)))
        #expect(layout.text == "Plan\n•\tone")
        #expect(layout.runs == markdown.runs)
        #expect(layout.indents == markdown.indents)
        #expect(layout.style.fontSize == 14)
        #expect(layout.box == CGSize(width: 200 - PenPostIt.textInsets.horizontal, height: 240 - PenPostIt.textInsets.vertical))
    }

    @Test("A note's text frame is its box less the insets")
    func textFrame() {
        let frame = PenPostIt.textFrame(inNoteOfWidth: 200, height: 100)
        #expect(frame == PenRect(x: 14, y: 14, width: 172, height: 72))
        #expect(PenPostIt.textFrame(inNoteOfWidth: 10, height: 10).width == 0)
    }
}
