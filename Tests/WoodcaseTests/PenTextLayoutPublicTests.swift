//
//  PenTextLayoutPublicTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
import Woodcase

/// ``PenTextLayout`` as RapidPro and Penumbra see it — imported without `@testable`, so
/// these fail to compile if the one layout call they share stops being public.
struct PenTextLayoutPublicTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let paragraph = "The quick brown fox jumps over the lazy dog near the riverbank"

    private static func style(_ vertical: PenTextAlignVertical = .top) -> PenTextStyle {
        PenTextStyle(fontFamily: "Inter", fontSize: 14, lineHeight: 1.25, textAlignVertical: vertical)
    }

    @Test("Lines are the ones PenTextLines sets, placed over the box's height")
    func placedLines() {
        let box = CGSize(width: 120, height: 200)
        let layout = PenTextLayout(text: Self.paragraph, style: Self.style(), box: box)
        let styled = Self.style().attributedString(Self.paragraph, for: .drawing(color: CGColor(gray: 0, alpha: 1)))
        let lines = PenTextLines(styled.string, width: 120, font: styled.font, fontSize: 14, lineHeight: 1.25)
        #expect(layout.lines.lines.count == lines.lines.count)
        #expect(layout.lines.lines.count > 1)
        #expect(layout.placed.map(\.1) == lines.placed(inBoxOfHeight: 200).map(\.1))
        #expect(layout.lines.pitch == 18)
    }

    @Test("The block's top follows the vertical alignment, its height rounded up", arguments: [
        PenTextAlignVertical.top, .middle, .bottom,
    ])
    func blockTop(alignment: PenTextAlignVertical) {
        let box = CGSize(width: 120, height: 200)
        let layout = PenTextLayout(text: Self.paragraph, style: Self.style(alignment), box: box)
        let block = ceil(layout.lines.height)
        let expected: CGFloat = switch alignment {
        case .top: 0
        case .middle: (200 - block) / 2
        case .bottom: 200 - block
        }
        #expect(layout.blockTop == expected)
        #expect(layout.blockRect == CGRect(x: 0, y: expected, width: 120, height: block))
    }

    @Test("textSpace maps each placed origin to its baseline in the box's y-down space")
    func textSpace() {
        let layout = PenTextLayout(text: Self.paragraph, style: Self.style(.middle), box: CGSize(width: 120, height: 200))
        for (index, (_, origin)) in layout.placed.enumerated() {
            let mapped = origin.applying(layout.textSpace)
            let baseline = layout.blockTop + layout.lines.firstBaseline + CGFloat(index) * layout.lines.pitch
            #expect(abs(mapped.y - baseline) < 1e-9)
            #expect(mapped.x == origin.x)
        }
    }

    @Test("A block taller than its box overflows; one that fits does not")
    func overflows() {
        let tall = PenTextLayout(text: Self.paragraph, style: Self.style(), box: CGSize(width: 120, height: 20))
        let roomy = PenTextLayout(text: Self.paragraph, style: Self.style(), box: CGSize(width: 120, height: 200))
        #expect(tall.overflows)
        #expect(!roomy.overflows)
    }

    @Test("Ink bounds union the glyphs, inside the block for a roomy box")
    func inkBounds() throws {
        let layout = PenTextLayout(text: Self.paragraph, style: Self.style(.bottom), box: CGSize(width: 120, height: 200))
        let ink = try #require(layout.inkBounds)
        #expect(ink.minY > layout.blockTop - 4)
        #expect(ink.maxY < 200 + 4)
        #expect(ink.width > 60)
    }

    @Test("Empty text sets no lines and no ink")
    func emptyText() {
        let layout = PenTextLayout(text: "", style: Self.style(), box: CGSize(width: 120, height: 40))
        #expect(layout.lines.lines.isEmpty)
        #expect(layout.inkBounds == nil)
    }

    @Test("A text node lays out its literal content in its own style, and nothing for an unresolved variable")
    func fromTextData() throws {
        let literal = PenNode.TextData(content: .literal("Hello"), fontFamily: .literal("Inter"))
        let layout = try #require(PenTextLayout(literal, box: CGSize(width: 100, height: 30)))
        #expect(layout.text == "Hello")
        #expect(layout.style == PenTextStyle(literal))
        let variable = PenNode.TextData(content: .variable("$copy"))
        #expect(PenTextLayout(variable, box: CGSize(width: 100, height: 30)) == nil)
        #expect(PenTextLayout(PenNode.TextData(), box: CGSize(width: 100, height: 30)) == nil)
    }
}
