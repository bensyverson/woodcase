//
//  PenTextSpansLayoutTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// How styled runs set: each run's face in the Core Text string, and lines whose height
/// follows the tallest face set on them, CSS-style, with the node's own style as the floor.
struct PenTextSpansLayoutTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let style = PenTextStyle(fontFamily: "Inter", fontSize: 14, lineHeight: 1.25)
    private static let natural = PenTextStyle(fontFamily: "Inter", fontSize: 14)
    private static let paragraph = "The quick brown fox jumps over the lazy dog near the riverbank"

    /// The font Core Text was handed at a UTF-16 index of a layout's string.
    private static func font(at index: Int, in layout: PenTextLayout) -> CTFont {
        let value = CFAttributedStringGetAttribute(layout.attributedString, index, kCTFontAttributeName, nil)
        return value as! CTFont
    }

    /// The glyph color Core Text was handed at a UTF-16 index of a layout's string.
    private static func color(at index: Int, in layout: PenTextLayout) -> CGColor? {
        let value = CFAttributedStringGetAttribute(layout.attributedString, index, kCTForegroundColorAttributeName, nil)
        return value.map { $0 as! CGColor }
    }

    /// A font's line metrics as the node's line height sets them: its pitch, and its
    /// height above and below the baseline.
    private static func metrics(of font: CTFont, lineHeight: Double?) -> (pitch: CGFloat, above: CGFloat, below: CGFloat) {
        let pitch = PenTextMeasurer.linePitch(lineHeight: lineHeight, fontSize: CTFontGetSize(font), font: font)
        let above = PenTextMeasurer.firstBaseline(of: font, lineHeight: lineHeight, pitch: pitch)
        return (pitch, above, pitch - above)
    }

    /// SF Pro, because the test fonts' Inter has no italic face.
    @Test("A run sets its own face in the string; the rest keeps the node's")
    func runFaceInString() {
        let layout = PenTextLayout(
            text: "Make this bold", style: PenTextStyle(fontFamily: "SF Pro", fontSize: 14),
            runs: [PenTextRun(start: 10, end: 14, fontSize: 20, fontWeight: 700, isItalic: true)],
            box: CGSize(width: 400, height: 100)
        )
        let plain = Self.font(at: 2, in: layout)
        let bold = Self.font(at: 11, in: layout)
        #expect(CTFontGetSize(plain) == 14)
        #expect(CTFontGetSize(bold) == 20)
        #expect(CTFontGetSymbolicTraits(bold).contains(.traitItalic))
        #expect(!CTFontGetSymbolicTraits(plain).contains(.traitItalic))
        #expect(plain == layout.font)
    }

    @Test("A bold run sets a wider line than the same text plain")
    func boldWidens() {
        let box = CGSize(width: 1000, height: 100)
        let plain = PenTextLayout(text: "Make this bold", style: Self.style, box: box)
        let bold = PenTextLayout(
            text: "Make this bold", style: Self.style,
            runs: [PenTextRun(start: 0, end: 14, fontWeight: 800)], box: box
        )
        let plainWidth = CTLineGetTypographicBounds(plain.lines.lines[0], nil, nil, nil)
        let boldWidth = CTLineGetTypographicBounds(bold.lines.lines[0], nil, nil, nil)
        #expect(boldWidth > plainWidth + 1)
    }

    @Test("A colored run carries its color; the rest carries the node's")
    func runColor() throws {
        let black = CGColor(gray: 0, alpha: 1)
        let layout = PenTextLayout(
            text: "red and black", style: Self.style,
            runs: [PenTextRun(start: 0, end: 3, fill: PenHexColor(red: 255, green: 0, blue: 0))],
            box: CGSize(width: 400, height: 40), color: black
        )
        let red = try #require(Self.color(at: 1, in: layout))
        let rest = try #require(Self.color(at: 8, in: layout))
        #expect(red.components?.map { Double($0) } == [1, 0, 0, 1])
        #expect(rest == black)
    }

    @Test("Without runs, every line is one pitch tall, its baseline the first baseline below its top")
    func plainBandsAreUniform() {
        let layout = PenTextLayout(text: Self.paragraph, style: Self.style, box: CGSize(width: 120, height: 400))
        let lines = layout.lines
        #expect(lines.lines.count > 2)
        #expect(lines.bands.count == lines.lines.count)
        for (index, band) in lines.bands.enumerated() {
            #expect(band.top == CGFloat(index) * lines.pitch)
            #expect(band.height == lines.pitch)
            #expect(band.baseline == band.top + lines.firstBaseline)
        }
        #expect(lines.height == CGFloat(lines.lines.count) * lines.pitch)
    }

    @Test("A line holding a larger run is as tall as that run's face needs; the others keep the pitch",
          arguments: [1.25, nil] as [Double?])
    func mixedSizeLine(lineHeight: Double?) throws {
        let style = PenTextStyle(fontFamily: "Inter", fontSize: 14, lineHeight: lineHeight)
        let text = "Small then BIG\nsmall again"
        let layout = PenTextLayout(
            text: text, style: style, runs: [PenTextRun(start: 11, end: 14, fontSize: 32)],
            box: CGSize(width: 1000, height: 400)
        )
        let lines = layout.lines
        try #require(lines.lines.count == 2)
        try #require(lines.bands.count == 2)
        let big = Self.metrics(of: Self.font(at: 12, in: layout), lineHeight: lineHeight)
        let small = Self.metrics(of: layout.font, lineHeight: lineHeight)
        #expect(lines.bands[0].top == 0)
        #expect(lines.bands[0].baseline == max(big.above, small.above))
        #expect(lines.bands[0].height == max(big.above, small.above) + max(big.below, small.below))
        #expect(lines.bands[0].height > lines.pitch)
        #expect(lines.bands[1].top == lines.bands[0].height)
        #expect(lines.bands[1].height == lines.pitch)
        #expect(lines.bands[1].baseline == lines.bands[1].top + lines.firstBaseline)
        #expect(lines.height == lines.bands[0].height + lines.pitch)
    }

    @Test("A smaller run never makes its line shorter than the node's pitch")
    func smallerRunKeepsPitch() throws {
        let layout = PenTextLayout(
            text: "tiny words here", style: Self.style, runs: [PenTextRun(start: 0, end: 4, fontSize: 6)],
            box: CGSize(width: 1000, height: 100)
        )
        try #require(layout.lines.bands.map(\.height) == [layout.lines.pitch])
        #expect(layout.lines.bands[0].baseline == layout.lines.firstBaseline)
    }

    @Test("Placed origins and geometry follow each line's band")
    func placedAndGeometryFollowBands() throws {
        let layout = PenTextLayout(
            text: "Small then BIG\nsmall again", style: Self.style, runs: [PenTextRun(start: 11, end: 14, fontSize: 32)],
            box: CGSize(width: 1000, height: 400)
        )
        let geometry = layout.geometry
        try #require(geometry.lines.count == 2)
        try #require(layout.lines.bands.count == 2)
        for (index, (_, origin)) in layout.placed.enumerated() {
            let band = layout.lines.bands[index]
            #expect(origin.applying(layout.textSpace).y == layout.blockTop + band.baseline)
            #expect(geometry.lines[index].baseline == Double(layout.blockTop + band.baseline))
            #expect(geometry.lines[index].band.y == Double(layout.blockTop + band.top))
            #expect(geometry.lines[index].band.height == Double(band.height))
        }
        #expect(layout.blockHeight == ceil(layout.lines.bands[0].height + layout.lines.bands[1].height))
    }

    @Test("A hard break after a larger line puts the empty caret line one pitch below it")
    func trailingEmptyLine() throws {
        let layout = PenTextLayout(
            text: "BIG\n", style: Self.style, runs: [PenTextRun(start: 0, end: 3, fontSize: 32)],
            box: CGSize(width: 1000, height: 400)
        )
        let geometry = layout.geometry
        try #require(geometry.lines.count == 2)
        let first = try #require(layout.lines.bands.first)
        #expect(geometry.lines[1].band.y == Double(first.top + first.height))
        #expect(geometry.lines[1].band.height == Double(layout.lines.pitch))
    }

    @Test("Measuring with runs gives the layout's block: its widest line and its summed bands")
    func measureMatchesLayout() {
        let runs = [PenTextRun(start: 11, end: 14, fontSize: 32, fontWeight: 700)]
        let text = "Small then BIG\nsmall again"
        let measured = PenTextMeasurer.measure(
            text, fontFamily: "Inter", fontSize: 14, lineHeight: 1.25, maxWidth: nil, runs: runs
        )
        let layout = PenTextLayout(text: text, style: Self.style, runs: runs, box: CGSize(width: 1000, height: 400))
        #expect(measured.height == layout.blockHeight)
        let plain = PenTextMeasurer.measure(text, fontFamily: "Inter", fontSize: 14, lineHeight: 1.25)
        #expect(measured.width > plain.width)
        #expect(measured.height > plain.height)
    }

    @Test("Wrapping at a width counts the wider bold run")
    func boldWraps() {
        let text = "aaaa bbbb cccc dddd"
        let plain = PenTextMeasurer.measure(text, fontFamily: "Inter", fontSize: 14, lineHeight: 1.25)
        let width = Double(plain.width) + 1
        let bold = PenTextMeasurer.measure(
            text, fontFamily: "Inter", fontSize: 14, lineHeight: 1.25, maxWidth: width,
            runs: [PenTextRun(start: 0, end: 19, fontWeight: 900)]
        )
        let twoLines: CGFloat = 2 * 18
        #expect(bold.height == twoLines)
    }

    @Test("Ink of a larger run reaches above the node's own ascent")
    func inkFollowsRuns() throws {
        let box = CGSize(width: 1000, height: 100)
        let plain = try #require(PenTextLayout(text: "small BIG", style: Self.style, box: box).inkBounds)
        let mixed = try #require(PenTextLayout(
            text: "small BIG", style: Self.style, runs: [PenTextRun(start: 6, end: 9, fontSize: 40)], box: box
        ).inkBounds)
        #expect(mixed.height > plain.height + 10)
    }

    @Test("A text node's layout sets its applied runs")
    func nodeLayoutUsesRuns() throws {
        let runs = [PenTextRun(start: 0, end: 4, fontSize: 30)]
        let node = PenNode.text(
            PenNode.TextData(content: .literal("Bold text"), fontFamily: .literal("Inter"), fontSize: .literal(14)),
            spans: PenTextSpans(text: "Bold text", runs: runs)
        )
        let layout = try #require(PenTextLayout(node, box: CGSize(width: 400, height: 100)))
        #expect(layout.runs == runs)
        #expect(CTFontGetSize(Self.font(at: 1, in: layout)) == 30)
        let stale = PenNode.text(
            PenNode.TextData(content: .literal("Bold text!"), fontFamily: .literal("Inter"), fontSize: .literal(14)),
            spans: PenTextSpans(text: "Bold text", runs: runs)
        )
        let plain = try #require(PenTextLayout(stale, box: CGSize(width: 400, height: 100)))
        #expect(plain.runs.isEmpty)
        #expect(CTFontGetSize(Self.font(at: 1, in: plain)) == 14)
    }

    @Test("The layout engine sizes a fit-content text node by its runs")
    func layoutEngineMeasuresRuns() throws {
        func layout(_ spans: PenTextSpans?) throws -> PenRect {
            let node = PenNode.text(PenNode.TextData(
                content: .literal("Bold text"), fontFamily: .literal("Inter"), fontSize: .literal(14),
                lineHeight: .literal(1.25)
            ), spans: spans)
            return try #require(PenLayoutEngine.layout(PenDocument(version: "2.20", children: [node]))["t"])
        }
        let plain = try layout(nil)
        let styled = try layout(PenTextSpans(text: "Bold text", runs: [PenTextRun(start: 0, end: 4, fontSize: 30)]))
        #expect(styled.width > plain.width)
        #expect(styled.height > plain.height)
        let stale = try layout(PenTextSpans(text: "Other", runs: [PenTextRun(start: 0, end: 4, fontSize: 30)]))
        #expect(stale == plain)
    }
}
