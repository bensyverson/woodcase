//
//  PenTextLinePlacementTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// The arithmetic behind where a line of text goes: its pitch, its first baseline, and the
/// origins ``PenTextLines`` hands the renderer.
struct PenTextLinePlacementTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static func inter(_ size: Double) -> CTFont {
        PenTextMeasurer.resolveFont(family: "Inter", size: size, weight: "400", style: "normal")
    }

    @Test("An explicit line height is rounded to a whole point, half up", arguments: [
        (14.0, 1.25, 18.0), (20.0, 1.13, 23.0), (18.0, 1.45, 26.0), (56.0, 0.9, 50.0),
    ])
    func explicitPitch(size: Double, lineHeight: Double, pitch: Double) {
        #expect(PenTextMeasurer.linePitch(lineHeight: lineHeight, fontSize: size, font: Self.inter(size)) == CGFloat(pitch))
    }

    @Test("No line height is the font's natural pitch")
    func naturalPitch() {
        let font = Self.inter(16)
        #expect(PenTextMeasurer.linePitch(lineHeight: nil, fontSize: 16, font: font)
            == PenTextMeasurer.naturalLineHeight(of: font))
    }

    /// Pen then rounds the baseline to a whole point: on `text-line-height-rounding` and
    /// `render-text-line-height` the rounded baseline scores 0.46–1.57 MAE where the exact
    /// one scores 0.51–1.57, and the unrounded one sits 1 px low on `loose-wrap`.
    @Test("An explicit line height splits its leading equally above and below the glyphs", arguments: [
        (32.0, 1.0), (24.0, 1.8), (56.0, 0.9), (14.0, 1.25),
    ])
    func halfLeading(size: Double, lineHeight: Double) {
        let font = Self.inter(size)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let pitch = PenTextMeasurer.linePitch(lineHeight: lineHeight, fontSize: size, font: font)
        let baseline = PenTextMeasurer.firstBaseline(of: font, lineHeight: lineHeight, pitch: pitch)
        #expect(baseline == (ascent + (pitch - ascent - descent) / 2).rounded())
    }

    @Test("A natural line keeps its first baseline at the rounded ascent")
    func naturalBaseline() {
        let font = Self.inter(16)
        #expect(PenTextMeasurer.firstBaseline(of: font, lineHeight: nil, pitch: 19) == CTFontGetAscent(font).rounded())
    }

    @Test("Lines sit one pitch apart, their origins in y-up space")
    func placedOrigins() throws {
        let font = Self.inter(16)
        let string = try #require(CFAttributedStringCreate(
            nil, "One\nTwo\nThree" as CFString, [kCTFontAttributeName: font] as CFDictionary
        ))
        let lines = PenTextLines(string, width: 300, pitch: 20, firstBaseline: 15)
        #expect(lines.lines.count == 3)
        #expect(lines.height == 60)
        let origins = lines.placed(inBoxOfHeight: 100).map(\.1)
        #expect(origins.map(\.y) == [85, 65, 45])
        #expect(origins.map(\.x) == [0, 0, 0])
    }
}
