//
//  PenNoteTextStyleSourceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Which key a note's drawn text style came from: its `metadata.woodcase`, the note's
/// own property (a legacy file), or the post-it default — so an inspector can say where
/// the value it shows lives (leaf Af2Qeg).
struct PenNoteTextStyleSourceTests {
    /// A node parsed from JSON.
    private func node(_ json: String) throws -> PenNode {
        let document = try PenParser.parse(#"{"version": "2.20", "children": ["# + json + "]}")
        return try #require(document.children.first)
    }

    @Test("A metadata value wins over the note's own key, which wins over the default")
    func precedence() throws {
        let both = try node("""
        {"id": "N1", "type": "note", "content": "hi", "fontSize": 18,
         "metadata": {"type": "woodcase", "woodcase": {"fontSize": 20}}}
        """)
        #expect(both.noteTextStyleSource(of: .fontSize) == .metadata)

        let legacy = try node(#"{"id": "N2", "type": "note", "content": "hi", "fontSize": 18}"#)
        #expect(legacy.noteTextStyleSource(of: .fontSize) == .property)
        #expect(legacy.noteTextStyle?.fontSize == 18)

        let bare = try node(#"{"id": "N3", "type": "note", "content": "hi"}"#)
        #expect(bare.noteTextStyleSource(of: .fontSize) == .default)
        #expect(bare.noteTextStyleSource(of: .lineHeight) == .default)
    }

    @Test("A metadata value the drawing skips is not named as the source")
    func skippedValues() throws {
        let note = try node("""
        {"id": "N1", "type": "note", "content": "hi", "fontSize": 18, "textAlign": "center",
         "metadata": {"type": "woodcase", "woodcase": {"fontSize": 0, "textAlign": "sideways",
           "lineHeight": "tall", "fontFamily": 7}}}
        """)
        #expect(note.noteTextStyleSource(of: .fontSize) == .property)
        #expect(note.noteTextStyleSource(of: .textAlign) == .property)
        #expect(note.noteTextStyleSource(of: .lineHeight) == .default)
        #expect(note.noteTextStyleSource(of: .fontFamily) == .default)
    }

    @Test("Every text-style key reports a source, on a prompt and a context too")
    func everyKey() throws {
        let prompt = try node("""
        {"id": "P1", "type": "prompt", "content": "go", "fontWeight": "700", "letterSpacing": 1,
         "fontStyle": "italic", "textAlignVertical": "middle",
         "metadata": {"type": "woodcase", "woodcase": {"fontFamily": "Inter", "fontWeight": 300}}}
        """)
        #expect(prompt.noteTextStyleSource(of: .fontFamily) == .metadata)
        #expect(prompt.noteTextStyleSource(of: .fontWeight) == .metadata)
        #expect(prompt.noteTextStyleSource(of: .fontStyle) == .property)
        #expect(prompt.noteTextStyleSource(of: .letterSpacing) == .property)
        #expect(prompt.noteTextStyleSource(of: .textAlignVertical) == .property)
        #expect(prompt.noteTextStyleSource(of: .textAlign) == .default)
        let context = try node(#"{"id": "C1", "type": "context", "content": "x"}"#)
        let styleKeys = PenMetadata.WoodcaseKey.allCases.filter { $0.group == .noteTextStyle }
        #expect(styleKeys.allSatisfy { context.noteTextStyleSource(of: $0) == .default })
    }

    @Test("A key that is not a text-style key, or a node that is not a note, has no source")
    func noSource() throws {
        let note = try node(#"{"id": "N1", "type": "note", "content": "hi"}"#)
        #expect(note.noteTextStyleSource(of: .tint) == nil)
        let text = try node(#"{"id": "T1", "type": "text", "content": "hi", "fontSize": 18}"#)
        #expect(text.noteTextStyleSource(of: .fontSize) == nil)
    }
}
