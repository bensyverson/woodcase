//
//  PenTextMeasurerTypesettingTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Measuring a text typesets it once: its width and line count both come from one pass of
/// Core Text's typesetter (a frame, for a justified paragraph), where they used to come
/// from two — the width from `CTFramesetterSuggestFrameSizeWithConstraints`, the line
/// count from a frame.
///
/// These tests prove the one-pass width is the suggested width *exactly*, not to within a
/// pixel, and the line count a frame's, over a matrix of faces, sizes, strings (wrapping and not, leading, trailing and
/// only whitespace, hard breaks, CJK, emoji, right-to-left, ligatures), wrapping widths,
/// letter spacing and alignments: a line's typographic width less its trailing whitespace,
/// never below zero. JetBrains Mono is left out — another suite owns its registration.
struct PenTextMeasurerTypesettingTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let strings = [
        "Hello", "Hello world", "Hello world ", "  lead", "trail   ", "a", " ", "   ",
        "The quick brown fox jumps over the lazy dog and keeps running far away",
        "Wrap me   please with   spaces   between words that go on",
        "Line one\nLine two\nLine three", "ends with newline\n", "\n", "a\n\nb",
        "日本語のテキストは折り返しがあります。長い文章を書いてみましょう。",
        "Emoji 😀🎉 in text 👍🏽 with more words here", "fi ffl Ta Vo AV kerning",
        "supercalifragilisticexpialidocious", "Tab\there", "مرحبا بالعالم hello",
        "Mixed 12,345.67 $ € numbers",
    ]

    private static let sizes: [CGFloat] = [9, 13, 14, 17.5, 32, 56]
    private static let widths: [CGFloat?] = [nil, 20, 73.5, 150, 200.25, 333]
    private static let letterSpacings: [CGFloat?] = [nil, 0.5, -0.3]
    private static let alignments: [CTTextAlignment?] = [nil, .center, .right, .justified]

    /// Every case of the matrix for one face, as attributed strings with their wrapping width.
    private static func cases(family: String) -> [(CFAttributedString, CGFloat?)] {
        sizes.flatMap { size in
            let font = PenTextMeasurer.resolveFont(family: family, size: size, weight: "400", style: "normal")
            let pitch = PenTextMeasurer.linePitch(lineHeight: 1.2, fontSize: size, font: font)
            return strings.flatMap { text in
                letterSpacings.flatMap { spacing in
                    alignments.flatMap { alignment in
                        var attributes: [CFString: Any] = [
                            kCTFontAttributeName: font,
                            kCTParagraphStyleAttributeName: PenTextMeasurer.paragraphStyle(
                                lineHeight: pitch, alignment: alignment
                            ),
                        ]
                        if let spacing {
                            attributes[kCTKernAttributeName] = spacing
                        }
                        let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
                        return widths.map { (string, $0) }
                    }
                }
            }
        }
    }

    /// The width `CTFramesetterSuggestFrameSizeWithConstraints` gives: the second pass
    /// measurement no longer makes.
    private static func suggestedWidth(_ string: CFAttributedString, width: CGFloat?) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let constraints = CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraints, nil
        ).width
    }

    /// The number of lines a `CTFrame` of the same width holds: what the renderer draws.
    private static func frameLineCount(_ string: CFAttributedString, width: CGFloat?) -> Int {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width ?? 1e7, height: 1e7), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return CFArrayGetCount(CTFrameGetLines(frame))
    }

    @Test(
        "One typesetting pass gives the suggested frame width and the frame's line count exactly",
        arguments: ["Inter", "IBM Plex Sans", "SF Pro", "Helvetica", "Menlo", "Times New Roman"]
    )
    func widthMatchesSuggestion(family: String) {
        var mismatches: [String] = []
        for (string, width) in Self.cases(family: family) {
            let typeset = PenTextMeasurer.typeset(string, width: width)
            let suggested = Self.suggestedWidth(string, width: width)
            let framed = Self.frameLineCount(string, width: width)
            if typeset.width != suggested || typeset.lineCount != framed {
                let text = CFAttributedStringGetString(string) as String
                mismatches.append(
                    "\(text.debugDescription) at \(String(describing: width)): "
                        + "width \(typeset.width) vs \(suggested), lines \(typeset.lineCount) vs \(framed)"
                )
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) mismatches, first: \(mismatches.prefix(5))")
    }

    @Test("Measurement is the suggested width, ceiled, over the line count times the pitch")
    func measurementMatchesTwoPassAnswer() {
        for (string, width) in Self.cases(family: "Inter") {
            let lineCount = Self.frameLineCount(string, width: width)
            let expected = CGSize(
                width: ceil(Self.suggestedWidth(string, width: width)),
                height: ceil(CGFloat(lineCount) * 17)
            )
            #expect(PenTextMeasurer.measureCFAttributedString(
                string, maxWidth: width.map(Double.init), lineHeight: 17
            ) == expected)
        }
    }
}
