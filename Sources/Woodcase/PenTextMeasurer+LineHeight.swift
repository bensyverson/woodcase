//
//  PenTextMeasurer+LineHeight.swift
//  Woodcase
//

import CoreText
import Foundation

public extension PenTextMeasurer {
    /// The height of one line of `font` in points, as Pen sets it: the font's ascent,
    /// descent and leading, rounded to a whole point.
    ///
    /// Text with no `lineHeight` is set at this pitch rather than Core Text's own natural
    /// line height, which rounds differently: Inter at 16 pt is 19.36 points, which Pen
    /// sets as 19 and a bare `CTFramesetter` as 20. Pen's layout of the same text
    /// (`Tests/WoodcaseTests/Fixtures/text-natural-line-height.layout.json`) rounds each
    /// line, so three lines of it are 57 points tall.
    ///
    /// - Parameter font: The resolved font.
    /// - Returns: The line pitch in points.
    static func naturalLineHeight(of font: CTFont) -> CGFloat {
        (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded()
    }

    /// The distance from one baseline to the next, as Pen sets it.
    ///
    /// An explicit `lineHeight` is `lineHeight × fontSize` rounded to a whole point, half
    /// up — per line, so three lines of 14 pt at 1.25 are 54 points tall, not 52.5
    /// (`Tests/WoodcaseTests/Fixtures/text-line-height-rounding.layout.json`, Pen's own).
    /// With none, it is ``naturalLineHeight(of:)``.
    ///
    /// - Parameters:
    ///   - lineHeight: The node's line height as a multiple of the font size, if it sets one.
    ///   - fontSize: The font size in points.
    ///   - font: The resolved font, whose metrics set the natural pitch.
    /// - Returns: The line pitch in points.
    static func linePitch(lineHeight: Double?, fontSize: Double, font: CTFont) -> CGFloat {
        lineHeight.map { CGFloat(fontSize * $0).rounded() } ?? naturalLineHeight(of: font)
    }

    /// Where the first baseline sits below the top of a text, as Pen places it.
    ///
    /// Under an explicit `lineHeight`, Pen follows CSS: the difference between the pitch
    /// and the font's ascent plus descent is split equally above and below the glyphs
    /// (half-leading), negative when lines are tighter than the font — and the baseline
    /// lands on a whole point. Rounding it matches Pen's exports better than not: 0.46–1.57
    /// MAE against 0.51–1.57 on `text-line-height-rounding` and `render-text-line-height`,
    /// where the exact baseline sits a pixel low at 2x on `loose-wrap`. A natural line
    /// keeps its baseline at the rounded ascent. The SwiftUI template's `PenFontModifier`
    /// places lines the same way.
    ///
    /// - Parameters:
    ///   - font: The resolved font.
    ///   - lineHeight: The node's line height as a multiple of the font size, if it sets one.
    ///   - pitch: The line pitch, from ``linePitch(lineHeight:fontSize:font:)``.
    /// - Returns: The first baseline's distance below the top, in points.
    static func firstBaseline(of font: CTFont, lineHeight: Double?, pitch: CGFloat) -> CGFloat {
        let ascent = CTFontGetAscent(font)
        guard lineHeight != nil else { return ascent.rounded() }
        let halfLeading = (pitch - ascent - CTFontGetDescent(font)) / 2
        return (ascent + halfLeading).rounded()
    }

    /// A paragraph style whose every line is exactly `points` tall.
    ///
    /// - Parameters:
    ///   - points: The line height in points.
    ///   - alignment: The horizontal alignment, or `nil` to leave Core Text's default.
    /// - Returns: The paragraph style.
    internal static func paragraphStyle(lineHeight points: CGFloat, alignment: CTTextAlignment? = nil) -> CTParagraphStyle {
        var lineHeight = points
        var ctAlignment = alignment ?? .natural
        return withUnsafeMutablePointer(to: &lineHeight) { heightPointer in
            withUnsafeMutablePointer(to: &ctAlignment) { alignmentPointer in
                var settings = [
                    CTParagraphStyleSetting(
                        spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: heightPointer
                    ),
                    CTParagraphStyleSetting(
                        spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: heightPointer
                    ),
                ]
                if alignment != nil {
                    settings.append(CTParagraphStyleSetting(
                        spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer
                    ))
                }
                return CTParagraphStyleCreate(&settings, settings.count)
            }
        }
    }
}
