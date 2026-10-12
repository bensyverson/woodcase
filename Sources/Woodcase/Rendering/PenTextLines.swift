import CoreGraphics
import CoreText
import Foundation

/// A text's lines as Pen sets them: Core Text breaks and aligns them, and each is placed
/// in a band below the last, its baseline where Pen puts it.
///
/// Core Text's own placement under a fixed line height puts the spare space — or the
/// shortfall, when lines are tighter than the font — on one side of the glyphs; Pen splits
/// it equally above and below (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``).
/// So only the lines and their horizontal origins are taken from Core Text.
///
/// A text in one face — every text without runs — sets every line one ``pitch`` tall
/// with its baseline ``firstBaseline`` below its top. A line holding a run in another face
/// or size is as tall as its tallest face needs, as CSS sets an inline box (``bands``).
///
/// ``PenTextLayout`` builds one for a text in its box, and is what a renderer or an editor
/// should call: it also places the block of lines by vertical alignment. Building one
/// directly with ``init(_:width:font:fontSize:lineHeight:)`` and drawing each of
/// ``placed(inBoxOfHeight:)``'s lines at its origin with `CTLineDraw` remains public for
/// RapidPro's `TextRasterizer` until it adopts ``PenTextLayout``.
///
/// Not `Friendly`: it holds `CTLine`s, which are neither `Codable` nor `Sendable`, and it
/// lives only for the duration of one draw.
public struct PenTextLines {
    /// The lines, top to bottom.
    public let lines: [CTLine]

    /// Each line's horizontal origin, as Core Text aligned it within the wrapping width.
    public let lineStarts: [CGFloat]

    /// The node's own line pitch: the distance from one baseline to the next where every
    /// face on both lines is the node's, and the least any line is tall.
    public let pitch: CGFloat

    /// The node's own first baseline: its distance below the top of a line set in the
    /// node's face alone.
    public let firstBaseline: CGFloat

    /// Each line's band, top to bottom: where it starts, how tall it is, and where its
    /// baseline sits, in points below the top of the block. The bands tile the block, but
    /// for a paragraph's spacing (``PenParagraphIndent/spacingAfter``), left between them.
    public let bands: [Band]

    /// The block's height: the bands' total, with any paragraph spacing between them — the
    /// line count times the pitch for a text in one face and no spacing.
    public var height: CGFloat {
        bands.last.map { $0.top + $0.height } ?? 0
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
            firstBaseline: PenTextMeasurer.firstBaseline(of: font, lineHeight: lineHeight, pitch: pitch),
            lineHeight: lineHeight
        )
    }

    /// Breaks a styled text into lines at `width` and places them in their bands.
    ///
    /// - Parameters:
    ///   - styled: The text, styled, with its node's font metrics.
    ///   - width: The wrapping width, which horizontal alignment is measured against.
    init(_ styled: PenStyledText, width: CGFloat) {
        self.init(
            styled.string, width: width, pitch: styled.pitch, firstBaseline: styled.firstBaseline,
            lineHeight: styled.lineHeight
        )
    }

    /// Breaks `attributedString` into lines at `width`.
    ///
    /// - Parameters:
    ///   - attributedString: The text, styled.
    ///   - width: The wrapping width, which horizontal alignment is measured against.
    ///   - pitch: The node's distance from one baseline to the next.
    ///   - firstBaseline: The node's first baseline below the top of a line.
    ///   - lineHeight: The line height as a multiple of each font's size, or `nil` for
    ///     natural: what sets a run's band in another face.
    init(
        _ attributedString: CFAttributedString,
        width: CGFloat,
        pitch: CGFloat,
        firstBaseline: CGFloat,
        lineHeight: Double?
    ) {
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
        bands = Self.bands(
            of: lines, in: attributedString,
            strut: Strut(pitch: pitch, firstBaseline: firstBaseline, lineHeight: lineHeight)
        )
    }

    /// Each line with its origin in Core Text's y-up space, over a box `height` tall
    /// whose top the block starts at.
    ///
    /// - Parameter boxHeight: The height of the y-up space the origins are measured in.
    /// - Returns: The lines, top to bottom, each with its baseline origin.
    public func placed(inBoxOfHeight boxHeight: CGFloat) -> [(CTLine, CGPoint)] {
        lines.indices.map { index in
            (lines[index], CGPoint(x: lineStarts[index], y: boxHeight - bands[index].baseline))
        }
    }
}
