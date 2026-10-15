import CoreGraphics
import CoreText
import Foundation

public extension PenTextRenderer {
    /// The attribute that marks a run struck through.
    ///
    /// Core Text has no native strikethrough, so ``PenTextStyle/attributedString(_:runs:indents:for:)``
    /// marks struck runs with this key and ``drawStrikethrough(lines:in:)`` strokes them.
    /// Public so that another renderer (RapidPro) draws the same bar rather than a copy.
    static var strikethroughKey: CFString {
        "WoodcaseStrikethrough" as CFString
    }

    /// Draws strikethrough lines for runs marked with the custom strikethrough attribute.
    ///
    /// Iterates the lines and their runs, finding runs with the `strikethroughKey`
    /// attribute set, and fills a bar a little above the baseline of each: as thick as the
    /// run's font draws its underline, with its edges on whole device pixels, as Core Text
    /// places an underline's — so the two decorations of one text weigh the same, as they
    /// do in Core Text and browsers.
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

                guard let font = attrs[kCTFontAttributeName] as! CTFont? else { continue }

                // Get the color for this run
                let color = attrs[kCTForegroundColorAttributeName] as! CGColor?
                    ?? CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0, 0, 0, 1])!

                // Calculate run position
                let startOffset = CTLineGetOffsetForStringIndex(line, runRange.location, nil)
                let endOffset = CTLineGetOffsetForStringIndex(
                    line, runRange.location + runRange.length, nil
                )

                let bar = strikethroughBar(
                    x: lineOrigin.x + min(startOffset, endOffset), width: abs(endOffset - startOffset),
                    baseline: lineOrigin.y, font: font
                )
                context.saveGState()
                context.setFillColor(color)
                context.fill(snappedToPixels(bar, in: context))
                context.restoreGState()
            }
        }
    }

    /// The underline and strikethrough bars of one line, as rectangles: those of every run
    /// the node's paint colors, leaving out runs with a fill of their own
    /// (``runFillKey``), whose bars go with them (``decorationBars(of:in:at:)``).
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
    internal static func decorationBars(of line: CTLine, at origin: CGPoint) -> [CGRect] {
        (CTLineGetGlyphRuns(line) as! [CTRun])
            .filter { !hasOwnFill($0) }
            .flatMap { decorationBars(of: $0, in: line, at: origin) }
    }

    /// The underline and strikethrough bars of one run, as rectangles.
    ///
    /// - Parameters:
    ///   - run: The run.
    ///   - line: The line it is on.
    ///   - origin: The line's origin in Core Text's y-up space.
    /// - Returns: The bars, in the same y-up space.
    internal static func decorationBars(of run: CTRun, in line: CTLine, at origin: CGPoint) -> [CGRect] {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName] else { return [] }
        let font = value as! CTFont
        let range = CTRunGetStringRange(run)
        let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
        let end = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
        let span = (x: origin.x + min(start, end), width: abs(end - start))

        var bars: [CGRect] = []
        if let style = attributes[kCTUnderlineStyleAttributeName] as? NSNumber, style.intValue != 0 {
            let thickness = CTFontGetUnderlineThickness(font)
            let center = origin.y + CTFontGetUnderlinePosition(font)
            bars.append(CGRect(x: span.x, y: center - thickness / 2, width: span.width, height: thickness))
        }
        if attributes[strikethroughKey] != nil {
            bars.append(strikethroughBar(x: span.x, width: span.width, baseline: origin.y, font: font))
        }
        return bars
    }

    /// How far up the ascent the strikethrough sits, as a fraction of it.
    static let strikethroughAscentFraction: CGFloat = 0.35

    /// The strikethrough bar of a run, before snapping: centered
    /// ``strikethroughAscentFraction`` of the font's ascent above the baseline, as thick as
    /// the font's underline.
    ///
    /// - Parameters:
    ///   - x: The run's left edge.
    ///   - width: The run's width.
    ///   - baseline: The line's baseline, in Core Text's y-up space.
    ///   - font: The run's font.
    /// - Returns: The bar, in the same space.
    static func strikethroughBar(x: CGFloat, width: CGFloat, baseline: CGFloat, font: CTFont) -> CGRect {
        let thickness = CTFontGetUnderlineThickness(font)
        let center = baseline + CTFontGetAscent(font) * strikethroughAscentFraction
        return CGRect(x: x, y: center - thickness / 2, width: width, height: thickness)
    }

    /// A bar with its top and bottom moved to whole device pixels, at least one pixel apart,
    /// so it draws solid rather than as two half-covered rows.
    private static func snappedToPixels(_ bar: CGRect, in context: CGContext) -> CGRect {
        let device = context.convertToDeviceSpace(bar)
        let height = max(1, device.height.rounded())
        let top = (device.midY - height / 2).rounded()
        let snapped = CGRect(x: device.minX, y: top, width: device.width, height: height)
        return context.convertToUserSpace(snapped)
    }
}
