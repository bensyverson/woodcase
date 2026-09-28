//
//  PenTextLinesPublicTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
import Woodcase

/// ``PenTextLines`` as another renderer sees it — imported without `@testable`, so these
/// tests fail to compile if the entry point RapidPro places its lines through stops being
/// public.
struct PenTextLinesPublicTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static func setLines(lineHeight: Double?) -> (PenTextLines, CTFont) {
        let font = PenTextMeasurer.resolveFont(family: "Inter", size: 14, weight: "400", style: "normal")
        let attributes = [kCTFontAttributeName: font] as CFDictionary
        let text = "The quick brown fox jumps over the lazy dog near the riverbank" as CFString
        let string = CFAttributedStringCreate(nil, text, attributes)!
        return (PenTextLines(string, width: 120, font: font, fontSize: 14, lineHeight: lineHeight), font)
    }

    @Test("An explicit line height sets the rounded pitch and Pen's half-leading baseline")
    func explicitLineHeight() {
        let (lines, font) = Self.setLines(lineHeight: 1.25)
        #expect(lines.pitch == 18)
        #expect(lines.firstBaseline == PenTextMeasurer.firstBaseline(of: font, lineHeight: 1.25, pitch: 18))
        #expect(lines.lines.count > 1)
        #expect(lines.height == CGFloat(lines.lines.count) * 18)
    }

    @Test("No line height sets the font's natural pitch, its baseline at the rounded ascent")
    func naturalLineHeight() {
        let (lines, font) = Self.setLines(lineHeight: nil)
        #expect(lines.pitch == PenTextMeasurer.naturalLineHeight(of: font))
        #expect(lines.firstBaseline == CTFontGetAscent(font).rounded())
    }

    @Test("Placed lines step down one pitch from the first baseline, from the box's top")
    func placedLines() {
        let (lines, _) = Self.setLines(lineHeight: 1.25)
        let placed = lines.placed(inBoxOfHeight: 200)
        #expect(placed.count == lines.lines.count)
        for (index, (_, origin)) in placed.enumerated() {
            let baseline: CGFloat = lines.firstBaseline + CGFloat(index) * 18
            #expect(origin.y == 200 - baseline)
            #expect(origin.x == lines.lineStarts[index])
        }
    }
}
