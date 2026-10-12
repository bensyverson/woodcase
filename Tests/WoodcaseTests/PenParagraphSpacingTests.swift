//
//  PenParagraphSpacingTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Space after a paragraph (``PenParagraphIndent/spacingAfter``): a general text-layout
/// value that a note's markdown sets after each heading, about half a body line (Ben's
/// ruling on the rev 2 look, 2026-10-11).
struct PenParagraphSpacingTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let style = PenTextStyle(fontFamily: "Inter", fontSize: 13, fontWeight: 400, lineHeight: 1.35)

    @Test("A paragraph's spacing after pushes the next line down by that much, and no other")
    func spacingPushesTheNextLine() {
        let plain = PenTextLayout(text: "Plan\nOne\nTwo", style: Self.style, box: CGSize(width: 200, height: 200))
        let spaced = PenTextLayout(
            text: "Plan\nOne\nTwo", style: Self.style,
            indents: [PenParagraphIndent(start: 0, end: 5, firstLineIndent: 0, headIndent: 0, spacingAfter: 9)],
            box: CGSize(width: 200, height: 200)
        )
        let plainBands = plain.lines.bands
        let spacedBands = spaced.lines.bands
        #expect(spacedBands[0] == plainBands[0])
        #expect(abs(spacedBands[1].top - plainBands[1].top - 9) < 0.001)
        #expect(abs(spacedBands[2].top - plainBands[2].top - 9) < 0.001)
        #expect(abs(spaced.lines.height - plain.lines.height - 9) < 0.001)
        let geometry = spaced.geometry
        #expect(abs(geometry.lines[1].baseline - plain.geometry.lines[1].baseline - 9) < 0.001)
    }

    @Test("A last paragraph adds no space below the block")
    func noTrailingSpace() {
        let plain = PenTextLayout(text: "Plan", style: Self.style, box: CGSize(width: 200, height: 200))
        let spaced = PenTextLayout(
            text: "Plan", style: Self.style,
            indents: [PenParagraphIndent(start: 0, end: 4, firstLineIndent: 0, headIndent: 0, spacingAfter: 9)],
            box: CGSize(width: 200, height: 200)
        )
        #expect(spaced.lines.height == plain.lines.height)
    }

    @Test("A paragraph that wraps adds its space once, after its last line")
    func wrappedParagraph() {
        let text = "The quick brown fox jumps over the lazy dog\nNext"
        let indent = PenParagraphIndent(start: 0, end: 44, firstLineIndent: 0, headIndent: 0, spacingAfter: 9)
        let spaced = PenTextLayout(text: text, style: Self.style, indents: [indent], box: CGSize(width: 90, height: 400))
        let plain = PenTextLayout(text: text, style: Self.style, box: CGSize(width: 90, height: 400))
        let count = spaced.lines.bands.count
        #expect(count > 2)
        for index in 0 ..< count - 1 {
            #expect(spaced.lines.bands[index] == plain.lines.bands[index])
        }
        #expect(abs(spaced.lines.bands[count - 1].top - plain.lines.bands[count - 1].top - 9) < 0.001)
    }

    @Test("Measuring counts the spacing, so a note grows by it")
    func measuringCountsSpacing() {
        let indent = PenParagraphIndent(start: 0, end: 5, firstLineIndent: 0, headIndent: 0, spacingAfter: 9)
        let plain = PenTextMeasurer.measure("Plan\nOne", fontFamily: "Inter", fontSize: 13, lineHeight: 1.35, maxWidth: 200)
        let spaced = PenTextMeasurer.measure(
            "Plan\nOne", fontFamily: "Inter", fontSize: 13, lineHeight: 1.35, maxWidth: 200, indents: [indent]
        )
        #expect(spaced.height == plain.height + 9)
    }

    @Test("A caret on the empty line after a spaced paragraph sits below the spacing")
    func emptyLineAfterSpacing() {
        let spaced = PenTextLayout(
            text: "Plan\n", style: Self.style,
            indents: [PenParagraphIndent(start: 0, end: 5, firstLineIndent: 0, headIndent: 0, spacingAfter: 9)],
            box: CGSize(width: 200, height: 200)
        )
        let plain = PenTextLayout(text: "Plan\n", style: Self.style, box: CGSize(width: 200, height: 200))
        let geometry = spaced.geometry
        #expect(geometry.lines.count == 2)
        #expect(abs(geometry.lines[1].band.y - plain.geometry.lines[1].band.y - 9) < 0.001)
    }

    @Test("A heading is followed by paragraph spacing in layout: about half a body line")
    func headingSpacing() throws {
        let note = PenNoteMarkdown("# Plan\nbody", fontSize: 13)
        let heading = try #require(note.indents.first)
        #expect(heading.range == 0 ..< 5)
        #expect(heading.firstLineIndent == 0 && heading.headIndent == 0)
        #expect(abs(heading.spacingAfter - 13 * 1.35 / 2) < 0.01)
        let layout = PenTextLayout(
            text: note.displayText, style: Self.style, runs: note.runs, indents: note.indents,
            box: CGSize(width: 200, height: 200)
        )
        let bands = layout.lines.bands
        #expect(abs(bands[1].top - (bands[0].top + bands[0].height) - heading.spacingAfter) < 0.001)
    }

    @Test("A list item has no spacing after it")
    func listItemsHaveNone() {
        #expect(PenNoteMarkdown("- a\n- b", fontSize: 13).indents.allSatisfy { $0.spacingAfter == 0 })
    }
}
