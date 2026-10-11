//
//  PenTextOffsetMapTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The map between a note's markdown and its display text, both ways, in UTF-16 offsets.
struct PenTextOffsetMapTests {
    @Test("Hidden syntax is skipped from display to source, and collapses from source to display")
    func boldMapping() {
        let map = PenNoteMarkdown("**bold** x").offsetMap
        #expect(map.sourceLength == 10)
        #expect(map.displayLength == 6)
        #expect(map.sourceOffset(forDisplayOffset: 0) == 2)
        #expect(map.sourceOffset(forDisplayOffset: 5) == 9)
        #expect(map.sourceOffset(forDisplayOffset: 6) == 10)
        #expect(map.displayOffset(forSourceOffset: 0) == 0)
        #expect(map.displayOffset(forSourceOffset: 3) == 1)
        #expect(map.displayOffset(forSourceOffset: 9) == 5)
        #expect(map.displayOffset(forSourceOffset: 10) == 6)
    }

    @Test("A display range maps to the source of its characters, not the syntax around them")
    func rangeMapping() {
        let map = PenNoteMarkdown("**bold** x").offsetMap
        #expect(map.sourceRange(forDisplayRange: 0 ..< 4) == 2 ..< 6)
        #expect(map.displayRange(forSourceRange: 0 ..< 8) == 0 ..< 4)
        #expect(map.displayRange(forSourceRange: 0 ..< 2).isEmpty)
    }

    @Test("A marker glyph maps to the whole syntax it stands for")
    func markerMapping() {
        let note = PenNoteMarkdown("- [ ] item")
        let map = note.offsetMap
        #expect(map.sourceOffset(forDisplayOffset: 0) == 0)
        #expect(map.sourceOffset(forDisplayOffset: 2) == 6)
        #expect(map.sourceRange(forDisplayRange: 0 ..< 1) == 0 ..< 6)
        #expect(map.sourceRange(forDisplayRange: 2 ..< 6) == 6 ..< 10)
    }

    @Test("The pieces tile both strings, and verbatim offsets round-trip")
    func tilingAndRoundTrip() {
        let source = "# Head *it*\n- [x] done @ben\n  1. **n** \\* x\n`c` 👍🏽 _e_"
        let note = PenNoteMarkdown(source)
        let map = note.offsetMap
        #expect(map.sourceLength == source.utf16.count)
        #expect(map.displayLength == note.displayText.utf16.count)
        for (previous, next) in zip(map.pieces, map.pieces.dropFirst()) {
            #expect(previous.source.upperBound == next.source.lowerBound)
            #expect(previous.display.upperBound == next.display.lowerBound)
        }
        let sourceUnits = Array(source.utf16)
        let displayUnits = Array(note.displayText.utf16)
        for piece in map.pieces where piece.isVerbatim {
            #expect(Array(sourceUnits[piece.source]) == Array(displayUnits[piece.display]))
            for offset in piece.display {
                #expect(map.displayOffset(forSourceOffset: map.sourceOffset(forDisplayOffset: offset)) == offset)
            }
        }
    }
}
