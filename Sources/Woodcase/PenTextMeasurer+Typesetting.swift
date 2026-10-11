//
//  PenTextMeasurer+Typesetting.swift
//  Woodcase
//

import CoreText
import Foundation

extension PenTextMeasurer {
    /// What one typesetting pass says about a text: how wide its lines run and how many
    /// there are.
    struct Typeset: Friendly {
        /// The widest line's typographic width, less its trailing whitespace and never
        /// below zero — exactly `CTFramesetterSuggestFrameSizeWithConstraints`' width
        /// (`PenTextMeasurerTypesettingTests`).
        let width: CGFloat

        /// The number of lines the text breaks into — exactly as many as a `CTFrame` of
        /// the same width holds.
        let lineCount: Int
    }

    /// Breaks a text into lines at `width`, once, and measures them.
    ///
    /// Measurement used to typeset every text twice: the suggested frame size for the
    /// width, and a frame for the line count. A typesetter alone answers both, and is
    /// cheaper than a frame, which also places and aligns every line. A justified
    /// paragraph is the exception: a frame stretches its lines to the width, and the
    /// suggested width counts the stretch, so it is measured from a frame.
    ///
    /// - Parameters:
    ///   - string: The styled text.
    ///   - width: The wrapping width, or `nil` for no wrapping.
    /// - Returns: The lines' width and count.
    static func typeset(_ string: CFAttributedString, width: CGFloat?) -> Typeset {
        let lines = lines(of: string, width: width)
        return Typeset(width: widest(lines), lineCount: lines.count)
    }

    /// Measures a styled text's block once: its widest line and its lines' bands
    /// (``PenTextLines/bands``), so a line holding a larger run counts as tall as it is set.
    ///
    /// - Parameters:
    ///   - styled: The text, styled, with its node's line metrics.
    ///   - width: The wrapping width, or `nil` for no wrapping.
    /// - Returns: The block's size, rounded up to whole points.
    static func measureBlock(_ styled: PenStyledText, width: CGFloat?) -> CGSize {
        let lines = lines(of: styled.string, width: width)
        let bands = PenTextLines.bands(
            of: lines, in: styled.string,
            strut: PenTextLines.Strut(pitch: styled.pitch, firstBaseline: styled.firstBaseline, lineHeight: styled.lineHeight)
        )
        let height = bands.last.map { $0.top + $0.height } ?? 0
        return CGSize(width: ceil(widest(lines)), height: ceil(height))
    }

    /// The lines a text breaks into at `width`: a frame's for a justified paragraph, the
    /// typesetter's otherwise.
    ///
    /// - Parameters:
    ///   - string: The styled text.
    ///   - width: The wrapping width, or `nil` for no wrapping.
    /// - Returns: The lines, top to bottom.
    private static func lines(of string: CFAttributedString, width: CGFloat?) -> [CTLine] {
        // An unwrapped measurement gets a width no line reaches.
        let unbounded: CGFloat = 1e7
        return isJustified(string)
            ? framedLines(string, width: width ?? unbounded)
            : typesetLines(string, width: width ?? unbounded)
    }

    /// The widest line's typographic width, less its trailing whitespace, never below zero.
    ///
    /// - Parameter lines: The lines.
    /// - Returns: The width in points.
    private static func widest(_ lines: [CTLine]) -> CGFloat {
        lines.reduce(CGFloat(0)) { widest, line in
            let inked = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CTLineGetTrailingWhitespaceWidth(line)
            return max(widest, inked)
        }
    }

    /// The lines Core Text's typesetter breaks `string` into at `width`, unaligned.
    ///
    /// - Parameters:
    ///   - string: The styled text.
    ///   - width: The wrapping width.
    /// - Returns: The lines, top to bottom.
    private static func typesetLines(_ string: CFAttributedString, width: CGFloat) -> [CTLine] {
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        let length = CFAttributedStringGetLength(string)
        var lines: [CTLine] = []
        var start = 0
        while start < length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }

    /// The lines of a `CTFrame` over `string` at `width`, aligned and justified.
    ///
    /// - Parameters:
    ///   - string: The styled text.
    ///   - width: The wrapping width.
    /// - Returns: The lines, top to bottom.
    private static func framedLines(_ string: CFAttributedString, width: CGFloat) -> [CTLine] {
        // Core Text lays out only the lines that fit the path, so the path is taller
        // than any text.
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1e7), transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return CTFrameGetLines(frame) as! [CTLine]
    }

    /// Whether any paragraph of `string` is justified.
    ///
    /// - Parameter string: The styled text.
    /// - Returns: `true` when a paragraph style in it sets `.justified` alignment.
    private static func isJustified(_ string: CFAttributedString) -> Bool {
        let length = CFAttributedStringGetLength(string)
        var index = 0
        while index < length {
            var run = CFRange(location: 0, length: 0)
            let value = CFAttributedStringGetAttribute(string, index, kCTParagraphStyleAttributeName, &run)
            if let value, CFGetTypeID(value) == CTParagraphStyleGetTypeID() {
                var alignment = CTTextAlignment.natural
                let style = value as! CTParagraphStyle
                CTParagraphStyleGetValueForSpecifier(
                    style, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment
                )
                if alignment == .justified {
                    return true
                }
            }
            index = run.location + max(run.length, 1)
        }
        return false
    }
}
