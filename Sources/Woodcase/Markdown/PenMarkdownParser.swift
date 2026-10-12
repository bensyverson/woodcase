//
//  PenMarkdownParser.swift
//  Woodcase
//

import Foundation

/// Parses a note's markdown, line by line, into ``PenNoteMarkdown``'s parts.
///
/// Notes are line-oriented: every source newline is a display newline (no paragraph
/// reflow, unlike CommonMark's soft breaks), and each line is a heading, a list item or
/// plain text. Inline styling (``PenMarkdownInline``) never crosses a line.
struct PenMarkdownParser {
    /// What one parse produces.
    struct Parsed {
        /// The display text.
        var displayText: String
        /// The runs over it.
        var runs: [PenTextRun]
        /// The list items' indents.
        var indents: [PenParagraphIndent]
        /// The checklist items.
        var checklistItems: [PenNoteMarkdown.ChecklistItem]
        /// Where each bullet's placeholder is.
        var bulletDisplayOffsets: [Int]
        /// The offset map.
        var offsetMap: PenTextOffsetMap
    }

    /// A paragraph's indent and spacing, waiting for its line's newline to close it.
    private struct OpenIndent {
        let start: Int
        let firstLineIndent: Double
        let headIndent: Double
        var spacingAfter: Double = 0
    }

    /// The source.
    let source: String
    /// The note's font size.
    let fontSize: Double

    /// Parses the whole source.
    func parse() -> Parsed {
        let units = Array(source.utf16)
        var output = PenMarkdownOutput(source: units)
        var lineStart = 0
        while true {
            let newline = units[lineStart...].firstIndex(of: PenMarkdownUnit.newline) ?? units.count
            var contentEnd = newline
            if contentEnd > lineStart, units[contentEnd - 1] == PenMarkdownUnit.carriageReturn { contentEnd -= 1 }
            let open = parseLine(lineStart ..< contentEnd, into: &output)
            output.keep(contentEnd ..< min(newline + 1, units.count))
            if let open {
                output.indents.append(PenParagraphIndent(
                    start: open.start, end: output.offset, firstLineIndent: open.firstLineIndent,
                    headIndent: open.headIndent, spacingAfter: open.spacingAfter
                ))
            }
            guard newline < units.count else { break }
            lineStart = newline + 1
        }
        let padding = PenNoteMarkdown.mentionPadding * fontSize
        output.runs = output.runs.map { run in
            guard run.mention != nil else { return run }
            var padded = run
            padded.inlinePadding = padding
            return padded
        }
        return output.parsed()
    }

    /// Parses one line, its newline excluded.
    ///
    /// - Returns: The indent a list item opens, or the spacing a heading leaves after
    ///   it, closed by the caller after the newline.
    private func parseLine(_ line: Range<Int>, into output: inout PenMarkdownOutput) -> OpenIndent? {
        let units = output.source
        if let level = headingLevel(of: line, in: units) {
            output.replace(line.lowerBound ..< line.lowerBound + level + 1, with: "")
            let start = output.offset
            let runIndex = output.runs.count
            PenMarkdownInline(range: line.lowerBound + level + 1 ..< line.upperBound, isBold: true).parse(into: &output)
            if output.offset > start {
                let scale = PenNoteMarkdown.headingScales[level - 1]
                output.runs.insert(
                    PenTextRun(start: start, end: output.offset, fontSize: scale * fontSize, fontWeight: PenNoteMarkdown.boldWeight),
                    at: runIndex
                )
            }
            return OpenIndent(
                start: start, firstLineIndent: 0, headIndent: 0, spacingAfter: PenNoteMarkdown.headingSpacing * fontSize
            )
        }
        guard let item = PenMarkdownListItem(line: line, in: units) else {
            PenMarkdownInline(range: line, isBold: false).parse(into: &output)
            return nil
        }
        let start = output.offset
        switch item.marker {
        case .bullet:
            output.bulletDisplayOffsets.append(start)
            output.replace(line.lowerBound ..< item.contentStart, with: PenNoteMarkdown.markerPlaceholder + "\t")
        case let .number(digits):
            output.replace(line.lowerBound ..< digits.lowerBound, with: "")
            output.keep(digits)
            output.replace(digits.upperBound ..< item.contentStart, with: "\t")
        case let .checkbox(marker, isChecked):
            output.replace(line.lowerBound ..< item.contentStart, with: PenNoteMarkdown.markerPlaceholder + "\t")
            output.checklistItems.append(PenNoteMarkdown.ChecklistItem(
                isChecked: isChecked, markerSourceRange: marker, boxDisplayRange: start ..< start + 1,
                lineDisplayRange: start ..< start
            ))
        }
        PenMarkdownInline(range: item.contentStart ..< line.upperBound, isBold: false).parse(into: &output)
        if case .checkbox = item.marker {
            output.checklistItems[output.checklistItems.count - 1].lineDisplayRange = start ..< output.offset
        }
        let step = PenNoteMarkdown.listIndent * fontSize
        return OpenIndent(start: start, firstLineIndent: Double(item.level) * step, headIndent: Double(item.level + 1) * step)
    }

    /// The heading level a line opens with — `#`, `##` or `###` and a space — or `nil`.
    private func headingLevel(of line: Range<Int>, in units: [UInt16]) -> Int? {
        let hashes = units[line].prefix { $0 == PenMarkdownUnit.hash }.count
        guard (1 ... PenNoteMarkdown.headingScales.count).contains(hashes),
              line.lowerBound + hashes < line.upperBound,
              units[line.lowerBound + hashes] == PenMarkdownUnit.space
        else { return nil }
        return hashes
    }
}
