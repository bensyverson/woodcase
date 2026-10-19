//
//  PenTextMeasurerSystemFontTests.swift
//  WoodcaseTests
//

import CoreText
import Foundation
import Testing
@testable import Woodcase

/// "SF Pro" (``PenTextStyle/defaultFontFamily``) draws as the system font on a Mac without
/// Apple's developer SF Pro installed, where the system font is the hidden `.SF NS` family
/// and Core Text would otherwise answer an unknown family with Helvetica (leaf hhRMBH).
///
/// Every test injects whether a family is installed, so none depends on whether this Mac
/// has the developer font.
struct PenTextMeasurerSystemFontTests {
    /// A lookup that knows only `installed`.
    private func installed(_ installed: String...) -> (String) -> Bool {
        { family in installed.contains(family) }
    }

    @Test("SF Pro draws from the developer font where it is installed")
    func sfProInstalled() {
        #expect(PenTextMeasurer.familySource(for: "SF Pro", isAvailable: installed("SF Pro")) == .family("SF Pro"))
    }

    @Test("SF Pro draws as the system font where it is not installed")
    func sfProMissing() {
        #expect(PenTextMeasurer.familySource(for: "SF Pro", isAvailable: installed()) == .systemFont)
    }

    @Test("An installed family draws from itself")
    func installedFamily() {
        #expect(PenTextMeasurer.familySource(for: "Inter", isAvailable: installed("Inter")) == .family("Inter"))
    }

    @Test("A missing family falls back to SF Pro, and so to the system font when SF Pro is missing too")
    func missingFamily() {
        #expect(PenTextMeasurer.familySource(for: "Inter", isAvailable: installed("SF Pro")) == .family("SF Pro"))
        #expect(PenTextMeasurer.familySource(for: "Inter", isAvailable: installed()) == .systemFont)
    }

    @Test("Without the developer font, SF Pro resolves to the system font at the weight asked for, not Helvetica")
    func resolvesToTheSystemFont() throws {
        let system = try #require(CTFontCreateUIFontForLanguage(.system, 16, nil))
        let regular = PenTextMeasurer.resolveFontUncached(
            family: "SF Pro", size: 16, weight: "normal", style: "normal",
            cache: FontResolutionCache(), isFamilyAvailable: installed()
        ).font
        let bold = PenTextMeasurer.resolveFontUncached(
            family: "SF Pro", size: 16, weight: "700", style: "normal",
            cache: FontResolutionCache(), isFamilyAvailable: installed()
        ).font

        #expect(CTFontCopyFamilyName(regular) as String == CTFontCopyFamilyName(system) as String)
        #expect(CTFontCopyFamilyName(regular) as String != "Helvetica")
        #expect(CTFontGetSize(bold) == 16)
        let variation = CTFontCopyVariation(bold) as? [Int: Double] ?? [:]
        #expect(variation[0x7767_6874] == 700)
        let weightTrait = { (font: CTFont) -> Double in
            let traits = CTFontCopyTraits(font) as? [CFString: Any] ?? [:]
            return (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
        }
        #expect(weightTrait(bold) > weightTrait(regular))
    }
}
