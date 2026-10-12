//
//  PenMarkdownOutput.swift
//  Woodcase
//

import Foundation

/// The display text a markdown parse writes, with the offset map, runs, indents,
/// checklist items and bullets it gathers on the way.
///
/// Every source code unit goes through ``keep(_:)`` or ``replace(_:with:)`` exactly once,
/// in order, so the pieces tile the source and the display text by construction.
struct PenMarkdownOutput {
    /// The source, in UTF-16 code units.
    let source: [UInt16]

    /// The display text so far, in UTF-16 code units.
    private(set) var display: [UInt16] = []

    /// The offset map's pieces so far.
    private(set) var pieces: [PenTextOffsetMap.Piece] = []

    /// The styled runs, offsets into the display text.
    var runs: [PenTextRun] = []

    /// The list items' indents.
    var indents: [PenParagraphIndent] = []

    /// The checklist items.
    var checklistItems: [PenNoteMarkdown.ChecklistItem] = []

    /// Where each bullet's placeholder is in the display text.
    var bulletDisplayOffsets: [Int] = []

    /// Where the next display code unit goes.
    var offset: Int {
        display.count
    }

    /// Copies a stretch of the source to the display text as it is.
    ///
    /// - Parameter range: The source's UTF-16 range; an empty one copies nothing.
    mutating func keep(_ range: Range<Int>) {
        guard !range.isEmpty else { return }
        let start = offset
        display += source[range]
        if var last = pieces.last, last.isVerbatim, last.source.upperBound == range.lowerBound {
            last.source = last.source.lowerBound ..< range.upperBound
            last.display = last.display.lowerBound ..< offset
            pieces[pieces.count - 1] = last
        } else {
            pieces.append(PenTextOffsetMap.Piece(source: range, display: start ..< offset, isVerbatim: true))
        }
    }

    /// Writes syntax as what it displays: nothing (`**`), or a placeholder and a tab
    /// (`- ` → `␣⇥`).
    ///
    /// - Parameters:
    ///   - range: The syntax's UTF-16 range in the source.
    ///   - text: What it displays as.
    mutating func replace(_ range: Range<Int>, with text: String) {
        guard !range.isEmpty || !text.isEmpty else { return }
        let start = offset
        display += Array(text.utf16)
        pieces.append(PenTextOffsetMap.Piece(source: range, display: start ..< offset, isVerbatim: false))
    }

    /// The finished parse.
    func parsed() -> PenMarkdownParser.Parsed {
        PenMarkdownParser.Parsed(
            displayText: String(decoding: display, as: UTF16.self),
            runs: runs,
            indents: indents,
            checklistItems: checklistItems,
            bulletDisplayOffsets: bulletDisplayOffsets,
            offsetMap: PenTextOffsetMap(pieces: pieces)
        )
    }
}
