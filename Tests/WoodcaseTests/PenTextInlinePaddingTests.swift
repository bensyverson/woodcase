//
//  PenTextInlinePaddingTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// A run's inline padding (``PenTextRun/inlinePadding``), laid out as CSS lays out
/// horizontal padding on an inline element: extra advance before and after the run, in the
/// one layout every consumer shares, so wrapping, measuring, carets and drawing agree. A
/// note's mention pill is its first user.
struct PenTextInlinePaddingTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let style = PenTextStyle(fontFamily: "Inter", fontSize: 13, fontWeight: 400, lineHeight: 1.35)

    private func carets(_ text: String, runs: [PenTextRun] = []) -> [Int: Double] {
        let layout = PenTextLayout(text: text, style: Self.style, runs: runs, box: CGSize(width: 400, height: 100))
        var carets: [Int: Double] = [:]
        for line in layout.geometry.lines {
            for caret in line.carets {
                carets[caret.index] = caret.x
            }
        }
        return carets
    }

    /// Where each UTF-16 offset's first glyph starts, line by line, in the box.
    private func glyphStarts(_ text: String, runs: [PenTextRun] = []) -> [Int: Double] {
        let layout = PenTextLayout(text: text, style: Self.style, runs: runs, box: CGSize(width: 400, height: 100))
        var starts: [Int: Double] = [:]
        for (line, lineStart) in zip(layout.lines.lines, layout.lines.lineStarts) {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var positions = [CGPoint](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                for glyph in 0 ..< count where starts[indices[glyph]] == nil {
                    starts[indices[glyph]] = Double(lineStart + positions[glyph].x)
                }
            }
        }
        return starts
    }

    @Test("Mid-line, a padded run's glyphs move right by its padding, and what follows by twice it")
    func midLine() throws {
        let plain = glyphStarts("x @ben y")
        let padded = glyphStarts("x @ben y", runs: [PenTextRun(start: 2, end: 6, inlinePadding: 3)])
        #expect(try abs(#require(padded[1]) - #require(plain[1])) < 0.001, "the space before the run is unmoved")
        #expect(try abs(#require(padded[2]) - #require(plain[2]) - 3) < 0.001, "the run starts after its padding")
        #expect(try abs(#require(padded[5]) - #require(plain[5]) - 3) < 0.001)
        #expect(try abs(#require(padded[6]) - #require(plain[6]) - 6) < 0.001, "what follows starts after the padding")
        #expect(try abs(#require(padded[7]) - #require(plain[7]) - 6) < 0.001)
    }

    @Test("At a paragraph's start, a padded run starts its padding in from the text column")
    func paragraphStart() throws {
        let padded = carets("@ben y\n@ana z", runs: [
            PenTextRun(start: 0, end: 4, inlinePadding: 3), PenTextRun(start: 7, end: 11, inlinePadding: 3),
        ])
        #expect(try abs(#require(padded[0]) - 3) < 0.001)
        #expect(try abs(#require(padded[7]) - 3) < 0.001)
    }

    @Test("Measuring counts the padding, so a text that holds one is wider")
    func measuring() {
        let plain = PenTextMeasurer.measure("x @ben y", fontFamily: "Inter", fontSize: 13, lineHeight: 1.35)
        let padded = PenTextMeasurer.measure(
            "x @ben y", fontFamily: "Inter", fontSize: 13, lineHeight: 1.35,
            runs: [PenTextRun(start: 2, end: 6, inlinePadding: 3)]
        )
        #expect(abs(padded.width - plain.width - 6) <= 1)
    }

    @Test("Padding can move a line break, and the layout and the measurer agree on it")
    func reflows() {
        let text = "aaaa bbbb @cccc dddd"
        let run = PenTextRun(start: 10, end: 15, inlinePadding: 12)
        let plainWidth = PenTextMeasurer.measure(text, fontFamily: "Inter", fontSize: 13, lineHeight: 1.35).width
        let width = plainWidth + 6
        let plain = PenTextLayout(text: text, style: Self.style, box: CGSize(width: width, height: 100))
        let padded = PenTextLayout(text: text, style: Self.style, runs: [run], box: CGSize(width: width, height: 100))
        #expect(plain.lines.lines.count == 1)
        #expect(padded.lines.lines.count == 2)
        let measured = PenTextMeasurer.measure(
            text, fontFamily: "Inter", fontSize: 13, lineHeight: 1.35, maxWidth: width, runs: [run]
        )
        #expect(measured.height == padded.blockHeight)
    }

    @Test("Padding is a size, so it stays in a measurement's cache key")
    func cacheKey() {
        let request = PenTextMeasureRequest(text: "x @ben y", runs: [PenTextRun(start: 2, end: 6, inlinePadding: 3)])
        #expect(request.ignoringColor.runs.first?.inlinePadding == 3)
    }

    @Test("A note's mention carries the note's mention padding: 3 points at 13")
    func mentionPadding() throws {
        let note = PenNoteMarkdown("Ask @claude", fontSize: 13)
        let run = try #require(note.runs.first { $0.mention == "claude" })
        #expect(abs((run.inlinePadding ?? 0) - 3) < 0.001)
        #expect(PenNoteMarkdown("Ask @claude", fontSize: 26).runs.first { $0.mention != nil }?.inlinePadding == 2 * (run.inlinePadding ?? 0))
    }
}
