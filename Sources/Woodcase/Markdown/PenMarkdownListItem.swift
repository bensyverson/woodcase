//
//  PenMarkdownListItem.swift
//  Woodcase
//

import Foundation

/// A line that opens a list item: its nesting level, its marker, and where its words
/// start.
struct PenMarkdownListItem {
    /// What starts the item.
    enum Marker {
        /// `-`, `*` or `+`.
        case bullet
        /// A number and its `.` or `)`: the source range of both, shown as written.
        case number(Range<Int>)
        /// `- [ ]` or `- [x]`: the source range of the brackets, and whether it is ticked.
        case checkbox(Range<Int>, isChecked: Bool)
    }

    /// The most digits a list number may have, as CommonMark allows.
    private static let maxDigits = 9

    /// The nesting level: each ``PenNoteMarkdown/spacesPerLevel`` leading spaces, or
    /// each tab, is one.
    let level: Int

    /// The item's marker.
    let marker: Marker

    /// The source offset its words start at, past the marker and one space.
    let contentStart: Int

    /// Reads a list item from a line, or `nil` when the line is not one.
    ///
    /// - Parameters:
    ///   - line: The line's UTF-16 range, its newline excluded.
    ///   - units: The source.
    init?(line: Range<Int>, in units: [UInt16]) {
        let end = line.upperBound
        var index = line.lowerBound
        var spaces = 0
        var tabs = 0
        while index < end, units[index] == PenMarkdownUnit.space || units[index] == PenMarkdownUnit.tab {
            if units[index] == PenMarkdownUnit.space { spaces += 1 } else { tabs += 1 }
            index += 1
        }
        level = spaces / PenNoteMarkdown.spacesPerLevel + tabs
        let isSpace = { (offset: Int) in offset < end && units[offset] == PenMarkdownUnit.space }
        guard index < end else { return nil }

        if [PenMarkdownUnit.dash, PenMarkdownUnit.asterisk, PenMarkdownUnit.plus].contains(units[index]), isSpace(index + 1) {
            let box = index + 2
            if box + 3 <= end, units[box] == PenMarkdownUnit.openBracket, units[box + 2] == PenMarkdownUnit.closeBracket,
               [PenMarkdownUnit.space, PenMarkdownUnit.lowerX, PenMarkdownUnit.upperX].contains(units[box + 1]), box + 3 == end || isSpace(box + 3)
            {
                marker = .checkbox(box ..< box + 3, isChecked: units[box + 1] != PenMarkdownUnit.space)
                contentStart = min(box + 4, end)
            } else {
                marker = .bullet
                contentStart = box
            }
            return
        }

        let digits = units[index ..< end].prefix { $0 >= PenMarkdownUnit.zero && $0 <= PenMarkdownUnit.nine }.count
        let punctuation = index + digits
        guard (1 ... Self.maxDigits).contains(digits), punctuation < end,
              units[punctuation] == PenMarkdownUnit.period || units[punctuation] == PenMarkdownUnit.closeParen,
              isSpace(punctuation + 1)
        else { return nil }
        marker = .number(index ..< punctuation + 1)
        contentStart = punctuation + 2
    }
}
