//
//  PenTextLines+Bands.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation

public extension PenTextLines {
    /// One line's band: the slice of the block it fills, and where its baseline sits.
    ///
    /// ## How tall a line is
    ///
    /// Each face set on a line — the node's own, and each run's — needs a height above the
    /// baseline and one below it, measured as the node's own line is: its pitch
    /// (``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)`` at its own size, so an
    /// explicit `lineHeight` multiplies each run's size as CSS's unitless `line-height`
    /// does) split around its baseline as Pen places the node's
    /// (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``). The line is as tall as
    /// the most any face needs above plus the most any needs below, with its baseline
    /// between — CSS's line box with the node's own style as its strut. So a larger run
    /// pushes its line's baseline down and the lines after it lower, a smaller run never
    /// makes a line shorter than the node's pitch, and a line in the node's face alone is
    /// exactly one pitch tall with its baseline at ``PenTextLines/firstBaseline`` —
    /// the same lines every text without runs has always set. Faces Core Text substitutes
    /// for missing glyphs (an emoji) do not count; only the faces the style and runs name.
    struct Band: Friendly {
        /// The band's top, in points below the top of the block.
        public var top: CGFloat

        /// The band's height in points.
        public var height: CGFloat

        /// The line's baseline, in points below the top of the block.
        public var baseline: CGFloat

        /// Creates a band.
        ///
        /// - Parameters:
        ///   - top: The band's top below the block's.
        ///   - height: Its height.
        ///   - baseline: The line's baseline below the block's top.
        public init(top: CGFloat, height: CGFloat, baseline: CGFloat) {
            self.top = top
            self.height = height
            self.baseline = baseline
        }
    }

    /// The node's own line metrics: the floor every line's band is measured from.
    internal struct Strut {
        /// The node's line pitch.
        let pitch: CGFloat
        /// The node's first baseline below the top of a line.
        let firstBaseline: CGFloat
        /// The line height as a multiple of a font's size, or `nil` for natural.
        let lineHeight: Double?
    }

    /// Places lines in bands, each below the last, with a paragraph's spacing
    /// (``PenParagraphIndent/spacingAfter``) between its last line and the next.
    ///
    /// The spacing is a gap between bands, not part of either: a band stays as tall as its
    /// line, so a caret's height and a selection's rect are the line's own.
    ///
    /// - Parameters:
    ///   - lines: The lines, top to bottom.
    ///   - string: The string they were set from, whose font attributes name each line's
    ///     faces and whose paragraph styles carry each paragraph's spacing.
    ///   - strut: The node's own line metrics.
    /// - Returns: One band per line.
    internal static func bands(of lines: [CTLine], in string: CFAttributedString, strut: Strut) -> [Band] {
        let oneFace = isInOneFace(string)
        var top: CGFloat = 0
        return lines.map { line in
            var above = strut.firstBaseline
            var below = strut.pitch - strut.firstBaseline
            if !oneFace {
                for font in faces(in: string, range: CTLineGetStringRange(line)) {
                    let pitch = PenTextMeasurer.linePitch(
                        lineHeight: strut.lineHeight, fontSize: CTFontGetSize(font), font: font
                    )
                    let ascent = PenTextMeasurer.firstBaseline(of: font, lineHeight: strut.lineHeight, pitch: pitch)
                    above = max(above, ascent)
                    below = max(below, pitch - ascent)
                }
            }
            let band = Band(top: top, height: above + below, baseline: top + above)
            top += band.height + paragraphSpacing(after: line, in: string)
            return band
        }
    }

    /// The space a line leaves below it before the next: its paragraph's spacing when it
    /// is the paragraph's last line — it ends in a paragraph separator — else 0.
    ///
    /// The last line of a text never ends in a separator unless an empty line follows it,
    /// so a block's height never ends in spacing; an editor's caret on that empty line
    /// sits below the gap (``PenTextLayout/geometry``).
    ///
    /// - Parameters:
    ///   - line: A line set from `string`.
    ///   - string: The styled string.
    /// - Returns: The spacing in points.
    internal static func paragraphSpacing(after line: CTLine, in string: CFAttributedString) -> CGFloat {
        let range = CTLineGetStringRange(line)
        guard range.length > 0 else { return 0 }
        let last = range.location + range.length - 1
        let text = CFAttributedStringGetString(string)
        let unit = CFStringGetCharacterAtIndex(text, last)
        // The separators Core Text ends a paragraph at; a CRLF ends at its LF.
        let separators: Set<UniChar> = [0x0A, 0x0D, 0x85, 0x2029]
        guard separators.contains(unit),
              let value = CFAttributedStringGetAttribute(string, last, kCTParagraphStyleAttributeName, nil),
              CFGetTypeID(value) == CTParagraphStyleGetTypeID()
        else { return 0 }
        var spacing: CGFloat = 0
        CTParagraphStyleGetValueForSpecifier(
            value as! CTParagraphStyle, .paragraphSpacing, MemoryLayout<CGFloat>.size, &spacing
        )
        return max(0, spacing)
    }

    /// Whether one font attribute covers the whole string, so every line is set in it.
    private static func isInOneFace(_ string: CFAttributedString) -> Bool {
        let length = CFAttributedStringGetLength(string)
        guard length > 0 else { return true }
        var effective = CFRange(location: 0, length: 0)
        _ = CFAttributedStringGetAttributeAndLongestEffectiveRange(
            string, 0, kCTFontAttributeName, CFRange(location: 0, length: length), &effective
        )
        return effective.length >= length
    }

    /// The fonts the string's attributes name over `range`, in order, repeats included.
    private static func faces(in string: CFAttributedString, range: CFRange) -> [CTFont] {
        var fonts: [CTFont] = []
        var index = range.location
        let end = range.location + range.length
        while index < end {
            var effective = CFRange(location: 0, length: 0)
            let value = CFAttributedStringGetAttribute(string, index, kCTFontAttributeName, &effective)
            if let value, CFGetTypeID(value) == CTFontGetTypeID() {
                fonts.append(value as! CTFont)
            }
            index = max(effective.location + effective.length, index + 1)
        }
        return fonts
    }
}
