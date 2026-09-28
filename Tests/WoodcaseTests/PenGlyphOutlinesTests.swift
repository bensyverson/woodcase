import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Pins the public glyph outlines: the clip a non-solid paint is drawn through, in the
/// node's y-down space.
struct PenGlyphOutlinesTests {
    /// Maps Core Text's y-up space over a box 60 pt tall into y-down.
    private static let textSpace = CGAffineTransform(translationX: 0, y: 60).scaledBy(x: 1, y: -1)

    private static func line(_ text: String, underline: Bool = false) -> CTLine {
        var attributes: [CFString: Any] = [kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 40, nil)]
        if underline {
            attributes[kCTUnderlineStyleAttributeName] = CTUnderlineStyle.single.rawValue as CFNumber
        }
        return CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        )
    }

    @Test("The outline covers the line's glyphs where it is placed, flipped into y-down")
    func outlineCoversGlyphs() {
        let line = Self.line("MM")
        let origin = CGPoint(x: 5, y: 20)
        let outlines = PenGlyphOutlines(lines: [(line, origin)], textSpace: Self.textSpace)
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            .offsetBy(dx: origin.x, dy: origin.y)
            .applying(Self.textSpace)
        let bounds = outlines.path.boundingBoxOfPath
        #expect(abs(bounds.minX - glyphs.minX) < 0.01 && abs(bounds.maxX - glyphs.maxX) < 0.01)
        #expect(abs(bounds.minY - glyphs.minY) < 0.01 && abs(bounds.maxY - glyphs.maxY) < 0.01)
        #expect(outlines.colorRuns.isEmpty)
    }

    @Test("An underline reaches below the glyphs")
    func underlineJoinsTheOutline() {
        let origin = CGPoint(x: 5, y: 20)
        let plain = PenGlyphOutlines(lines: [(Self.line("MM"), origin)], textSpace: Self.textSpace)
        let underlined = PenGlyphOutlines(lines: [(Self.line("MM", underline: true), origin)], textSpace: Self.textSpace)
        #expect(underlined.path.boundingBoxOfPath.maxY > plain.path.boundingBoxOfPath.maxY)
    }

    @Test("A colour glyph is kept aside, not outlined")
    func colourGlyphsKeptAside() {
        let outlines = PenGlyphOutlines(lines: [(Self.line("M😀"), CGPoint(x: 0, y: 20))], textSpace: Self.textSpace)
        #expect(outlines.colorRuns.count == 1)
        #expect(!outlines.path.isEmpty)
    }
}
