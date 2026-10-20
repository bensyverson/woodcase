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
        let set = lines(of: string, width: width)
        return Typeset(width: widest(set), lineCount: set.lines.count)
    }

    /// Measures a styled text's block once: its widest line and its lines' bands
    /// (``PenTextLines/bands``), so a line holding a larger run counts as tall as it is set.
    ///
    /// - Parameters:
    ///   - styled: The text, styled, with its node's line metrics.
    ///   - width: The wrapping width, or `nil` for no wrapping.
    /// - Returns: The block's size, rounded up to whole points.
    static func measureBlock(_ styled: PenStyledText, width: CGFloat?) -> CGSize {
        let set = lines(of: styled.string, width: width)
        let bands = PenTextLines.bands(
            of: set.lines, in: styled.string,
            strut: PenTextLines.Strut(pitch: styled.pitch, firstBaseline: styled.firstBaseline, lineHeight: styled.lineHeight)
        )
        let height = bands.last.map { $0.top + $0.height } ?? 0
        return CGSize(width: ceil(widest(set)), height: ceil(height))
    }

    /// The lines a text breaks into at `width`, each with where it starts: a frame's for
    /// a justified or indented paragraph, the typesetter's otherwise.
    ///
    /// The typesetter neither stretches a justified line nor honors a paragraph's
    /// indents (``PenParagraphIndent``), so either takes a frame, which sets both as the
    /// drawing's ``PenTextLines`` does.
    ///
    /// - Parameters:
    ///   - string: The styled text.
    ///   - width: The wrapping width, or `nil` for no wrapping.
    /// - Returns: The lines, top to bottom, and each line's start: its indent, else 0.
    private static func lines(of string: CFAttributedString, width: CGFloat?) -> (lines: [CTLine], starts: [CGFloat]) {
        // An unwrapped measurement gets a width no line reaches.
        let unbounded: CGFloat = 1e7
        let paragraphs = paragraphTraits(of: string)
        if paragraphs.isIndented {
            return framedLines(string, width: width ?? unbounded)
        }
        let lines = paragraphs.isJustified
            ? framedLines(string, width: width ?? unbounded).lines
            : typesetLines(string, width: width ?? unbounded)
        return (lines, Array(repeating: 0, count: lines.count))
    }

    /// The widest line's typographic width from its start, less its trailing whitespace,
    /// never below zero.
    ///
    /// - Parameter set: The lines and where each starts.
    /// - Returns: The width in points.
    private static func widest(_ set: (lines: [CTLine], starts: [CGFloat])) -> CGFloat {
        zip(set.lines, set.starts).reduce(CGFloat(0)) { widest, pair in
            let (line, start) = pair
            let inked = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - CTLineGetTrailingWhitespaceWidth(line)
            return max(widest, start + inked)
        }
    }

    /// The lines Core Text's typesetter breaks `string` into at `width`, unaligned.
    ///
    /// Gated by ``FontRegistryGate``: typesetting reaches `fontd` by itself, for a font's
    /// properties and for a fallback face.
    ///
    /// - Parameters:
    ///   - string: The styled text.
    ///   - width: The wrapping width.
    /// - Returns: The lines, top to bottom.
    private static func typesetLines(_ string: CFAttributedString, width: CGFloat) -> [CTLine] {
        FontRegistryGate.withAccess {
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
    }

    /// The lines of a `CTFrame` over `string` at `width`, aligned, justified and
    /// indented, with each line's start.
    ///
    /// Gated by ``FontRegistryGate``, as ``typesetLines(_:width:)`` is.
    ///
    /// - Parameters:
    ///   - string: The styled text.
    ///   - width: The wrapping width.
    /// - Returns: The lines, top to bottom, and each line's horizontal origin.
    private static func framedLines(_ string: CFAttributedString, width: CGFloat) -> (lines: [CTLine], starts: [CGFloat]) {
        // Core Text lays out only the lines that fit the path, so the path is taller
        // than any text.
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 1e7), transform: nil)
        let frame = FontRegistryGate.withAccess {
            CTFramesetterCreateFrame(
                CTFramesetterCreateWithAttributedString(string), CFRange(location: 0, length: 0), path, nil
            )
        }
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        return (lines, origins.map(\.x))
    }

    /// Whether any paragraph of `string` is justified, and whether any is indented.
    ///
    /// - Parameter string: The styled text.
    /// - Returns: Whether a paragraph style in it sets `.justified` alignment, and
    ///   whether one sets a first-line or head indent.
    private static func paragraphTraits(of string: CFAttributedString) -> (isJustified: Bool, isIndented: Bool) {
        let length = CFAttributedStringGetLength(string)
        var traits = (isJustified: false, isIndented: false)
        var index = 0
        while index < length {
            var run = CFRange(location: 0, length: 0)
            let value = CFAttributedStringGetAttribute(string, index, kCTParagraphStyleAttributeName, &run)
            if let value, CFGetTypeID(value) == CTParagraphStyleGetTypeID() {
                let style = value as! CTParagraphStyle
                var alignment = CTTextAlignment.natural
                CTParagraphStyleGetValueForSpecifier(style, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment)
                var firstLine: CGFloat = 0
                var head: CGFloat = 0
                CTParagraphStyleGetValueForSpecifier(style, .firstLineHeadIndent, MemoryLayout<CGFloat>.size, &firstLine)
                CTParagraphStyleGetValueForSpecifier(style, .headIndent, MemoryLayout<CGFloat>.size, &head)
                traits.isJustified = traits.isJustified || alignment == .justified
                traits.isIndented = traits.isIndented || firstLine != 0 || head != 0
            }
            index = run.location + max(run.length, 1)
        }
        return traits
    }
}
