//
//  PenTextOpticalSizeTests.swift
//  WoodcaseTests
//

import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Pen draws a variable font at its default optical size, whatever the point size.
///
/// Core Text moves a font's `opsz` axis to the point size on its own, so Inter above 14 pt
/// came out in its tighter display cut: 3 pt narrower than Pen at 32 pt for two letters,
/// 9 pt for a 56 pt word. Pen's widths match Inter's default optical size (14) at every
/// size from 12 to 32 pt (`text-natural-line-height.layout.json`) and at 40 and 56 pt
/// (`render-text-line-height.layout.json`).
struct PenTextOpticalSizeTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// The OpenType tag `opsz`, big-endian.
    private static let opticalSizeAxis = 0x6F70_737A

    @Test("An auto-width text node is as wide as Pen sets it")
    func widthMatchesPen() throws {
        let document = try PenParser.parse(
            contentsOf: Self.fixtures.appendingPathComponent("text-natural-line-height.pen")
        )
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixtures.appendingPathComponent("text-natural-line-height.layout.json"))
        )
        let actual = PenLayoutEngine.layout(document)
        let textIDs = expected.keys.filter { $0 != "prbA1" }.sorted()
        #expect(textIDs.count == 16)
        for id in textIDs {
            let rect = try #require(actual[id], "no rect for \(id)")
            let pen = try #require(expected[id])
            #expect(rect.width == pen.width, "\(id): Woodcase \(rect.width), Pen \(pen.width)")
        }
    }

    @Test("A variable font keeps its default optical size at a display size", arguments: [20.0, 32.0, 56.0])
    func opticalSizeStaysAtDefault(size: Double) {
        let font = PenTextMeasurer.resolveFont(family: "Inter", size: size, weight: "900", style: "normal")
        let variation = CTFontCopyVariation(font) as? [Int: Double] ?? [:]
        // Inter's default optical size is 14; Core Text omits an axis left at its default.
        #expect(variation[Self.opticalSizeAxis] ?? 14 == 14, "opsz \(variation[Self.opticalSizeAxis] ?? 14) at \(size) pt")
        #expect(variation[PenTextMeasurer.wghtAxisTag] == 900)
    }

    /// SF Pro is Woodcase's own fallback, not a face Pen draws, so there is no Pen to match:
    /// it keeps the optical sizing the system font is designed around, its text cut at
    /// text sizes. Pinned to its default optical size, 16 pt "Menu" came out 4 pt narrower.
    @Test("The fallback family keeps Core Text's automatic optical sizing")
    func fallbackKeepsAutomaticOpticalSize() throws {
        let family = PenTextMeasurer.defaultFontFamily
        let resolved = PenTextMeasurer.resolveFont(family: family, size: 16, weight: "400", style: "normal")
        let automatic = CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary), 16, nil
        )
        #expect(try Self.width(of: "Menu", in: resolved) == Self.width(of: "Menu", in: automatic))
    }

    private static func width(of text: String, in font: CTFont) throws -> Double {
        let string = try #require(CFAttributedStringCreate(
            nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary
        ))
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil)
    }
}
