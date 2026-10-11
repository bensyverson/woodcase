//
//  PenParagraphIndentLayoutTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// A paragraph's indents set its first line, its wrapped lines and its tab stop — and
/// the measurement the layout engine reads sets them the same way.
struct PenParagraphIndentLayoutTests {
    private static let style = PenTextStyle(fontSize: 14)
    private static let item = "•\tThe quick brown fox jumps over the lazy dog near the riverbank"
    private static let indent = PenParagraphIndent(start: 0, end: 64, firstLineIndent: 0, headIndent: 21)
    private static let box = CGSize(width: 160, height: 400)

    @Test("A wrapped line of an indented paragraph starts at its head indent")
    func wrappedLinesHang() throws {
        let layout = PenTextLayout(text: Self.item, style: Self.style, indents: [Self.indent], box: Self.box)
        try #require(layout.lines.lines.count > 1)
        #expect(layout.lines.lineStarts[0] == 0)
        for start in layout.lines.lineStarts.dropFirst() {
            #expect(start == 21)
        }
    }

    @Test("The tab after a marker reaches the head indent, so the words line up")
    func tabReachesHeadIndent() throws {
        let layout = PenTextLayout(text: Self.item, style: Self.style, indents: [Self.indent], box: Self.box)
        let first = try #require(layout.lines.lines.first)
        let wordStart = CTLineGetOffsetForStringIndex(first, 2, nil) + layout.lines.lineStarts[0]
        #expect(abs(wordStart - 21) < 0.5)
    }

    @Test("A nested item's first line starts at its first-line indent")
    func firstLineIndent() {
        let nested = PenParagraphIndent(start: 0, end: 64, firstLineIndent: 21, headIndent: 42)
        let layout = PenTextLayout(text: Self.item, style: Self.style, indents: [nested], box: Self.box)
        #expect(layout.lines.lineStarts.first == 21)
        #expect(layout.lines.lineStarts.dropFirst().allSatisfy { $0 == 42 })
    }

    @Test("Measuring with indents gives the height the layout sets, taller than without")
    func measurementAgrees() {
        // A deep head indent leaves the wrapped lines half the width, so they must be more.
        let deep = PenParagraphIndent(start: 0, end: 64, firstLineIndent: 0, headIndent: 80)
        let layout = PenTextLayout(text: Self.item, style: Self.style, indents: [deep], box: Self.box)
        let request = PenTextMeasureRequest(text: Self.item, fontSize: 14, maxWidth: 160, indents: [deep])
        let measured = PenLayoutEngine.defaultTextMeasurer(request)
        let plain = PenLayoutEngine.defaultTextMeasurer(request.measuring(Self.item, maxWidth: 160, runs: []))
        #expect(measured.height == Double(layout.blockHeight))
        #expect(measured.height > plain.height)
    }

    @Test("An unwrapped measurement counts the indent in the width")
    func unwrappedWidthCountsIndent() {
        let text = "•\tshort"
        let indent = PenParagraphIndent(start: 0, end: 7, firstLineIndent: 30, headIndent: 51)
        let indented = PenTextMeasurer.measure(text, fontSize: 14, indents: [indent])
        let word = PenTextMeasurer.measure("short", fontSize: 14)
        // The word starts at the tab stop, the head indent, so the line is 51 plus the word.
        #expect(abs(indented.width - (51 + word.width)) <= 1)
    }
}
