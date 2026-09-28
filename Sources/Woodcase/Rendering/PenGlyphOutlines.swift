import CoreGraphics
import CoreText
import Foundation

/// The union of a text layout's glyph outlines, as one path in the node's y-down space.
///
/// This is the clip a non-solid paint (``PenGlyphPaint/glyphOutlines``) is drawn through:
/// the same glyphs, at the same positions, that the Core Text route draws, plus the
/// underline and strikethrough bars, so text measurement and placement are exactly those
/// of the Core Text route.
///
/// Glyphs of a colour font (emoji) are bitmaps with no outline. Their runs are kept
/// aside and drawn by Core Text in their own colours, which is what the solid route
/// does with them too.
///
/// Public so that another renderer paints through the same outlines rather than a copy
/// of them: build one from ``PenTextLines/placed(inBoxOfHeight:)``'s lines (or an icon's
/// one line), fill each paint clipped to ``path``, and draw ``colorRuns`` with
/// ``drawColorGlyphs(in:)``.
///
/// Not `Friendly`: it holds a `CGPath` and `CTRun`s, which are neither `Codable` nor
/// `Sendable`, and it lives only for the duration of one draw.
public struct PenGlyphOutlines {
    /// A run of colour glyphs, drawn by Core Text rather than clipped to.
    public struct ColorRun {
        /// The run to draw.
        public let run: CTRun
        /// Its line's origin in Core Text's y-up space.
        public let origin: CGPoint
    }

    /// Every outlined glyph and decoration bar, in the node's y-down space.
    public let path: CGPath
    /// Runs from colour fonts, which have no outline.
    public let colorRuns: [ColorRun]
    /// Maps Core Text's y-up layout space into the node's y-down space.
    public let textSpace: CGAffineTransform

    /// Collects the outlines of lines placed at the given origins.
    ///
    /// - Parameters:
    ///   - lines: Each line with its origin in Core Text's y-up space.
    ///   - textSpace: Maps that y-up space into the node's y-down space.
    public init(lines: [(CTLine, CGPoint)], textSpace: CGAffineTransform) {
        let glyphs = CGMutablePath()
        let bars = CGMutablePath()
        var colorRuns: [ColorRun] = []
        for (line, origin) in lines {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                if Self.appendGlyphs(of: run, at: origin, to: glyphs, textSpace: textSpace) == false {
                    colorRuns.append(ColorRun(run: run, origin: origin))
                }
            }
            for bar in PenTextRenderer.decorationBars(of: line, at: origin) {
                bars.addRect(bar, transform: textSpace)
            }
        }
        // A bar crosses glyph contours of either winding direction, so merely appending it
        // could cancel to a hole where they overlap; a boolean union cannot.
        path = bars.isEmpty ? glyphs : glyphs.union(bars, using: .winding)
        self.colorRuns = colorRuns
        self.textSpace = textSpace
    }

    /// Draws the colour-glyph runs as Core Text would.
    ///
    /// - Parameter context: The context, in the node's y-down space.
    public func drawColorGlyphs(in context: CGContext) {
        for colorRun in colorRuns {
            context.saveGState()
            context.concatenate(textSpace)
            context.textPosition = colorRun.origin
            CTRunDraw(colorRun.run, context, CFRange(location: 0, length: 0))
            context.restoreGState()
        }
    }

    /// Adds a run's glyph outlines to `path`.
    ///
    /// - Returns: `false` when the run's font draws colour bitmaps, which have no outline
    ///   and nothing was added; `true` otherwise.
    private static func appendGlyphs(
        of run: CTRun,
        at origin: CGPoint,
        to path: CGMutablePath,
        textSpace: CGAffineTransform
    ) -> Bool {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName] else { return true }
        let font = value as! CTFont
        if CTFontGetSymbolicTraits(font).contains(.traitColorGlyphs) { return false }

        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        let runMatrix = CTRunGetTextMatrix(run)

        for (glyph, position) in zip(glyphs, positions) {
            guard let outline = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
            let placement = runMatrix
                .concatenating(CGAffineTransform(translationX: origin.x + position.x, y: origin.y + position.y))
                .concatenating(textSpace)
            path.addPath(outline, transform: placement)
        }
        return true
    }
}
