import CoreGraphics
import CoreText
import Foundation

/// A text's lines as Pen sets them: Core Text breaks and aligns them, and each is placed
/// one fixed pitch below the last, its first baseline where Pen puts it.
///
/// Core Text's own placement under a fixed line height puts the spare space — or the
/// shortfall, when lines are tighter than the font — on one side of the glyphs; Pen splits
/// it equally above and below (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``).
/// So only the lines and their horizontal origins are taken from Core Text.
///
/// This is the one place a renderer asks where a line of text goes: Woodcase's CG renderer
/// draws through it, and so does any other renderer that must land its lines on the same
/// pixel rows (RapidPro's `TextRasterizer`). Build one with
/// ``init(_:width:font:fontSize:lineHeight:)`` and draw each of
/// ``placed(inBoxOfHeight:)``'s lines at its origin with `CTLineDraw`.
///
/// Not `Friendly`: it holds `CTLine`s, which are neither `Codable` nor `Sendable`, and it
/// lives only for the duration of one draw.
public struct PenTextLines {
    /// The lines, top to bottom.
    public let lines: [CTLine]

    /// Each line's horizontal origin, as Core Text aligned it within the wrapping width.
    public let lineStarts: [CGFloat]

    /// The distance from one baseline to the next, in points.
    public let pitch: CGFloat

    /// The first baseline's distance below the top of the block, in points.
    public let firstBaseline: CGFloat

    /// The block's height: the line count times the pitch.
    public var height: CGFloat {
        CGFloat(lines.count) * pitch
    }

    /// Sets `attributedString` as Pen sets a text in `font`: breaks it at `width`, and
    /// places its lines at ``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)`` from
    /// ``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``.
    ///
    /// Horizontal alignment comes from the string's paragraph style; any line height the
    /// paragraph style sets is ignored, since the lines are placed here.
    ///
    /// - Parameters:
    ///   - attributedString: The text, styled.
    ///   - width: The wrapping width, which horizontal alignment is measured against.
    ///   - font: The text's resolved font (``PenTextMeasurer/resolveFont(family:size:weight:style:)``),
    ///     whose metrics set the natural pitch and the first baseline.
    ///   - fontSize: The font size in points.
    ///   - lineHeight: The text's line height as a multiple of the font size, or `nil` for
    ///     the font's natural line height.
    public init(
        _ attributedString: CFAttributedString,
        width: CGFloat,
        font: CTFont,
        fontSize: Double,
        lineHeight: Double?
    ) {
        let pitch = PenTextMeasurer.linePitch(lineHeight: lineHeight, fontSize: fontSize, font: font)
        self.init(
            attributedString,
            width: width,
            pitch: pitch,
            firstBaseline: PenTextMeasurer.firstBaseline(of: font, lineHeight: lineHeight, pitch: pitch)
        )
    }

    /// Breaks `attributedString` into lines at `width`.
    ///
    /// - Parameters:
    ///   - attributedString: The text, styled.
    ///   - width: The wrapping width, which horizontal alignment is measured against.
    ///   - pitch: The distance from one baseline to the next.
    ///   - firstBaseline: The first baseline's distance below the top of the block.
    init(_ attributedString: CFAttributedString, width: CGFloat, pitch: CGFloat, firstBaseline: CGFloat) {
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        // Tall enough for any text: Core Text leaves out the lines a path cannot hold, and
        // which lines those are is a question of its line heights, not Pen's.
        let unbounded: CGFloat = 1e7
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: unbounded), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        self.lines = lines
        lineStarts = origins.map(\.x)
        self.pitch = pitch
        self.firstBaseline = firstBaseline
    }

    /// Each line with its origin in Core Text's y-up space, over a box `height` tall
    /// whose top the block starts at.
    ///
    /// - Parameter boxHeight: The height of the y-up space the origins are measured in.
    /// - Returns: The lines, top to bottom, each with its baseline origin.
    public func placed(inBoxOfHeight boxHeight: CGFloat) -> [(CTLine, CGPoint)] {
        lines.indices.map { index in
            let baseline = firstBaseline + CGFloat(index) * pitch
            return (lines[index], CGPoint(x: lineStarts[index], y: boxHeight - baseline))
        }
    }
}
