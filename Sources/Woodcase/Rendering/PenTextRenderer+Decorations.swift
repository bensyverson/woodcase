import CoreGraphics
import CoreText
import Foundation

extension PenTextRenderer {
    /// Custom attribute key for marking strikethrough ranges.
    /// Core Text has no native strikethrough, so we draw it manually.
    static var strikethroughKey: CFString {
        "WoodcaseStrikethrough" as CFString
    }

    /// Draws strikethrough lines for runs marked with the custom strikethrough attribute.
    ///
    /// Iterates the lines and their runs, finding runs with the `strikethroughKey`
    /// attribute set, and draws a horizontal line a little above the baseline of each.
    ///
    /// - Parameters:
    ///   - lines: Each line with its origin in Core Text's y-up space.
    ///   - context: The context, already in that y-up space.
    static func drawStrikethrough(lines: [(CTLine, CGPoint)], in context: CGContext) {
        for (line, lineOrigin) in lines {
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]

            for run in runs {
                let runRange = CTRunGetStringRange(run)
                let attrs = CTRunGetAttributes(run) as NSDictionary

                guard attrs[strikethroughKey] != nil else { continue }

                // Get the font for this run to determine the line position
                guard let font = attrs[kCTFontAttributeName] as! CTFont? else { continue }
                let ascent = CTFontGetAscent(font)

                // Get the color for this run
                let color = attrs[kCTForegroundColorAttributeName] as! CGColor?
                    ?? CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 0, 1])!

                // Calculate run position
                let startOffset = CTLineGetOffsetForStringIndex(line, runRange.location, nil)
                let endOffset = CTLineGetOffsetForStringIndex(
                    line, runRange.location + runRange.length, nil
                )

                // Strikethrough at roughly 1/3 of ascent above baseline
                let strikeY = lineOrigin.y + ascent * strikethroughAscentFraction
                let lineWidth = strikethroughThickness

                context.saveGState()
                context.setStrokeColor(color)
                context.setLineWidth(lineWidth)
                context.move(to: CGPoint(x: lineOrigin.x + startOffset, y: strikeY))
                context.addLine(to: CGPoint(x: lineOrigin.x + endOffset, y: strikeY))
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    /// The underline and strikethrough bars of one line, as rectangles.
    ///
    /// The glyph-outline route clips its paint to these along with the glyphs, so a
    /// decorated gradient line carries the gradient through its bars. The strikethrough sits
    /// where ``drawStrikethrough(lines:in:)`` strokes it; the underline uses
    /// the font's own underline position and thickness.
    ///
    /// - Parameters:
    ///   - line: The line.
    ///   - origin: Its origin in Core Text's y-up space.
    /// - Returns: The bars, in the same y-up space.
    static func decorationBars(of line: CTLine, at origin: CGPoint) -> [CGRect] {
        var bars: [CGRect] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName] else { continue }
            let font = value as! CTFont
            let range = CTRunGetStringRange(run)
            let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
            let end = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
            let span = (x: origin.x + min(start, end), width: abs(end - start))

            if let style = attributes[kCTUnderlineStyleAttributeName] as? NSNumber, style.intValue != 0 {
                let thickness = CTFontGetUnderlineThickness(font)
                let center = origin.y + CTFontGetUnderlinePosition(font)
                bars.append(CGRect(x: span.x, y: center - thickness / 2, width: span.width, height: thickness))
            }
            if attributes[strikethroughKey] != nil {
                let center = origin.y + CTFontGetAscent(font) * strikethroughAscentFraction
                bars.append(CGRect(
                    x: span.x, y: center - strikethroughThickness / 2,
                    width: span.width, height: strikethroughThickness
                ))
            }
        }
        return bars
    }

    /// How far up the ascent the strikethrough sits, as a fraction of it.
    private static let strikethroughAscentFraction: CGFloat = 0.35

    /// The strikethrough's thickness in points.
    private static let strikethroughThickness: CGFloat = 1.0
}
