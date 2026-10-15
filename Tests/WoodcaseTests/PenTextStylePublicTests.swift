//
//  PenTextStylePublicTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
import Woodcase

/// Pins ``PenTextStyle`` and its attributed-string builder through the public API alone —
/// no `@testable` — as another renderer (RapidPro) consumes them.
@Suite("PenTextStyle public API")
struct PenTextStylePublicTests {
    /// The color the drawing purpose is handed in these tests.
    private static let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

    /// The attributes at the start of a built string.
    private static func attributes(of styled: PenStyledText) -> NSDictionary {
        CFAttributedStringGetAttributes(styled.string, 0, nil) as NSDictionary
    }

    /// The horizontal alignment a built string's paragraph style sets, or `nil` when
    /// its paragraph attribute is missing or not a paragraph style.
    private static func alignment(of styled: PenStyledText) -> CTTextAlignment? {
        guard let value = attributes(of: styled)[kCTParagraphStyleAttributeName],
              CFGetTypeID(value as CFTypeRef) == CTParagraphStyleGetTypeID()
        else { return nil }
        var alignment = CTTextAlignment.natural
        guard CTParagraphStyleGetValueForSpecifier(
            value as! CTParagraphStyle, .alignment, MemoryLayout<CTTextAlignment>.size, &alignment
        ) else { return nil }
        return alignment
    }

    @Test("An unstyled text is SF Pro 16, regular, upright, top-left, undecorated")
    func defaults() {
        let style = PenTextStyle()
        #expect(style.fontFamily == "SF Pro")
        #expect(style.fontSize == 16)
        #expect(style.fontWeight == 400)
        #expect(!style.isItalic)
        #expect(style.letterSpacing == nil)
        #expect(style.lineHeight == nil)
        #expect(style.textAlign == .left)
        #expect(style.textAlignVertical == .top)
        #expect(!style.underline)
        #expect(!style.strikethrough)
        #expect(PenTextStyle(PenNode.TextData()) == style)
    }

    @Test("A text node's style reads its literal properties")
    func fromTextData() {
        let data = PenNode.TextData(
            content: .literal("Hello"),
            fontFamily: .literal("Helvetica"),
            fontSize: .literal(24),
            fontWeight: .literal("bold"),
            fontStyle: .literal("Italic"),
            letterSpacing: .literal(1.5),
            lineHeight: .literal(1.25),
            textAlign: .center,
            textAlignVertical: .bottom,
            underline: .literal(true),
            strikethrough: .literal(true)
        )
        let style = PenTextStyle(data)
        #expect(style == PenTextStyle(
            fontFamily: "Helvetica", fontSize: 24, fontWeight: 700, isItalic: true,
            letterSpacing: 1.5, lineHeight: 1.25, textAlign: .center, textAlignVertical: .bottom,
            underline: true, strikethrough: true
        ))
    }

    @Test("A numeric weight is kept as its CSS number")
    func numericWeight() {
        let style = PenTextStyle(PenNode.TextData(fontWeight: .literal("450")))
        #expect(style.fontWeight == 450)
    }

    @Test("A style round-trips through JSON and hashes by value")
    func friendly() throws {
        let style = PenTextStyle(fontSize: 13, lineHeight: 1.4, textAlign: .justify)
        let decoded = try JSONDecoder().decode(PenTextStyle.self, from: JSONEncoder().encode(style))
        #expect(decoded == style)
        #expect(Set([style, decoded]).count == 1)
    }

    @Test("Building for drawing carries the font, color, kern, decorations and alignment")
    func drawingAttributes() throws {
        let style = PenTextStyle(
            fontSize: 20, letterSpacing: 2, lineHeight: 1.5, textAlign: .right,
            underline: true, strikethrough: true
        )
        let styled = style.attributedString("Hello", for: .drawing(color: Self.red))
        #expect(CFAttributedStringGetLength(styled.string) == 5)
        #expect(CTFontGetSize(styled.font) == 20)
        #expect(styled.pitch == 30)
        #expect(styled.firstBaseline == PenTextMeasurer.firstBaseline(of: styled.font, lineHeight: 1.5, pitch: 30))

        let attributes = Self.attributes(of: styled)
        let font = try #require(attributes[kCTFontAttributeName])
        #expect(CFEqual(font as CFTypeRef, styled.font))
        let color = try #require(attributes[kCTForegroundColorAttributeName])
        #expect(CFEqual(color as CFTypeRef, Self.red))
        #expect((attributes[kCTKernAttributeName] as? NSNumber)?.doubleValue == 2)
        #expect((attributes[kCTUnderlineStyleAttributeName] as? NSNumber)?.int32Value == CTUnderlineStyle.single.rawValue)
        #expect(attributes[PenTextRenderer.strikethroughKey] != nil)
        #expect(Self.alignment(of: styled) == .right)
    }

    @Test("Building for sizing leaves out color and alignment, and kern only when unset")
    func sizingAttributes() {
        let styled = PenTextStyle(textAlign: .justify).attributedString("Hello", for: .sizing)
        let attributes = Self.attributes(of: styled)
        #expect(attributes[kCTForegroundColorAttributeName] == nil)
        #expect(attributes[kCTKernAttributeName] == nil)
        #expect(Self.alignment(of: styled) == .natural)
    }

    @Test("Measuring a string is measuring its sizing build")
    func measureSharesTheBuilder() {
        let text = "The quick brown fox jumps over the lazy dog"
        let styled = PenTextStyle(fontSize: 15, letterSpacing: 0.5, lineHeight: 1.3)
            .attributedString(text, for: .sizing)
        let direct = PenTextMeasurer.measureCFAttributedString(styled.string, maxWidth: 120, lineHeight: styled.pitch)
        let measured = PenTextMeasurer.measure(text, fontSize: 15, letterSpacing: 0.5, lineHeight: 1.3, maxWidth: 120)
        #expect(measured == direct)
    }

    @Test("The strikethrough sits 0.35 of the ascent up")
    func strikethroughConstants() {
        #expect(PenTextRenderer.strikethroughAscentFraction == 0.35)
    }

    @Test("The strikethrough is as thick as the font's underline, snapped to whole pixels", arguments: [20.0, 40.0])
    func strikethroughMatchesUnderline(fontSize: Double) throws {
        let style = PenTextStyle(fontFamily: "Inter", fontSize: fontSize, strikethrough: true)
        let styled = style.attributedString("Hello", for: .drawing(color: Self.red))
        let line = CTLineCreateWithAttributedString(styled.string)
        let width = 200, height = 80
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // A fractional baseline: the bar must still land on whole pixel rows.
        PenTextRenderer.drawStrikethrough(lines: [(line, CGPoint(x: 0, y: 10.3))], in: context)
        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
        let column = 20
        let alphas = (0 ..< height).map { pixels[($0 * width + column) * 4 + 3] }.filter { $0 != 0 }
        let thickness = CTFontGetUnderlineThickness(styled.font)
        #expect(alphas.allSatisfy { $0 == 255 }, "\(alphas)")
        #expect(alphas.count == max(1, Int(thickness.rounded())), "\(alphas) for \(thickness)")
    }

    @Test("drawStrikethrough strokes a struck line and leaves an unstruck one alone")
    func drawsStrikethrough() throws {
        func inkedPixels(strikethrough: Bool) throws -> Int {
            let style = PenTextStyle(fontSize: 40, strikethrough: strikethrough)
            let styled = style.attributedString("—", for: .drawing(color: Self.red))
            let line = CTLineCreateWithAttributedString(styled.string)
            let width = 80, height = 60
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            PenTextRenderer.drawStrikethrough(lines: [(line, CGPoint(x: 0, y: 10))], in: context)
            let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: width * height * 4)
            return (0 ..< width * height).count(where: { pixels[$0 * 4 + 3] != 0 })
        }
        #expect(try inkedPixels(strikethrough: true) > 0)
        #expect(try inkedPixels(strikethrough: false) == 0)
    }
}
