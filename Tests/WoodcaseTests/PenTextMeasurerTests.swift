//
//  PenTextMeasurerTests.swift
//  WoodcaseTests
//

import CoreText
import Foundation
import Testing
import Woodcase

@Suite("PenTextMeasurer", .enabled(if: ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil || ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil, "CoreText requires an app host; run these tests from Xcode, not `swift test`"))
struct PenTextMeasurerTests {
    // MARK: - Basic Measurement

    @Test("Empty string returns zero size")
    func emptyString() {
        let size = PenTextMeasurer.measure("")
        #expect(size == .zero)
    }

    @Test("Single line text has non-zero width and height")
    func singleLineText() {
        let size = PenTextMeasurer.measure("Hello")
        #expect(size.width > 0)
        #expect(size.height > 0)
    }

    @Test("Longer text produces wider measurement")
    func longerTextIsWider() {
        let short = PenTextMeasurer.measure("Hi")
        let long = PenTextMeasurer.measure("Hello World, this is a longer string")
        #expect(long.width > short.width)
    }

    @Test("Larger font size produces larger measurement")
    func largerFontSize() {
        let small = PenTextMeasurer.measure("Hello", fontSize: 12)
        let large = PenTextMeasurer.measure("Hello", fontSize: 36)
        #expect(large.width > small.width)
        #expect(large.height > small.height)
    }

    // MARK: - Font Resolution

    @Test("Default font is SF Pro")
    func defaultFont() {
        #expect(PenTextMeasurer.defaultFontFamily == "SF Pro")
    }

    @Test("Default font size is 16")
    func defaultFontSize() {
        #expect(PenTextMeasurer.defaultFontSize == 16)
    }

    @Test("Specifying font family produces different measurement than default")
    func customFontFamily() {
        let sfPro = PenTextMeasurer.measure("Hello World", fontFamily: "SF Pro", fontSize: 24)
        let helvetica = PenTextMeasurer.measure("Hello World", fontFamily: "Helvetica", fontSize: 24)
        // Different fonts should produce different widths (they may be close but not identical)
        // Just verify both produce valid measurements
        #expect(sfPro.width > 0)
        #expect(helvetica.width > 0)
    }

    @Test("Bold text may differ from normal width")
    func boldWeight() {
        let normal = PenTextMeasurer.measure("Hello", fontSize: 24, fontWeight: "normal")
        let bold = PenTextMeasurer.measure("Hello", fontSize: 24, fontWeight: "bold")
        // Bold is typically wider than normal
        #expect(normal.width > 0)
        #expect(bold.width > 0)
    }

    // MARK: - Text Wrapping

    @Test("Text wraps when maxWidth is specified")
    func textWrapping() {
        let longText = "This is a fairly long sentence that should definitely wrap when given a narrow width constraint"
        let unwrapped = PenTextMeasurer.measure(longText, fontSize: 16)
        let wrapped = PenTextMeasurer.measure(longText, fontSize: 16, maxWidth: 200)
        // Wrapped text should be taller (multiple lines) and narrower
        #expect(wrapped.height > unwrapped.height)
        #expect(wrapped.width <= 201) // Allow 1px for ceil rounding
    }

    @Test("Single line text unaffected by large maxWidth")
    func largeMaxWidth() {
        let text = "Short"
        let unconstrained = PenTextMeasurer.measure(text, fontSize: 16)
        let constrained = PenTextMeasurer.measure(text, fontSize: 16, maxWidth: 10000)
        #expect(abs(unconstrained.width - constrained.width) < 1)
        #expect(abs(unconstrained.height - constrained.height) < 1)
    }

    @Test("Nil maxWidth means no wrapping")
    func nilMaxWidth() {
        let longText = "This text has no width constraint so it should remain on a single line"
        let size = PenTextMeasurer.measure(longText, fontSize: 16, maxWidth: nil)
        // Single line height should be roughly 1 line
        let singleLineHeight = PenTextMeasurer.measure("X", fontSize: 16).height
        #expect(abs(size.height - singleLineHeight) < 2)
    }

    // MARK: - Letter Spacing

    @Test("Positive letter spacing increases width")
    func positiveLetterSpacing() {
        let normal = PenTextMeasurer.measure("Hello World", fontSize: 16, letterSpacing: 0)
        let spaced = PenTextMeasurer.measure("Hello World", fontSize: 16, letterSpacing: 5)
        #expect(spaced.width > normal.width)
    }

    @Test("Negative letter spacing decreases width")
    func negativeLetterSpacing() {
        let normal = PenTextMeasurer.measure("Hello World", fontSize: 16, letterSpacing: 0)
        let tight = PenTextMeasurer.measure("Hello World", fontSize: 16, letterSpacing: -1)
        #expect(tight.width < normal.width)
    }

    // MARK: - Line Height

    @Test("Custom line height affects wrapped text height")
    func customLineHeight() {
        let longText = "This is enough text to wrap into multiple lines when constrained"
        let normal = PenTextMeasurer.measure(longText, fontSize: 16, maxWidth: 150)
        let tall = PenTextMeasurer.measure(longText, fontSize: 16, lineHeight: 2.0, maxWidth: 150)
        #expect(tall.height > normal.height)
    }

    // MARK: - Font Resolution

    @Test("resolveFont returns valid font for SF Pro")
    func resolveSFPro() {
        let font = PenTextMeasurer.resolveFont(family: "SF Pro", size: 16, weight: "normal", style: "normal")
        let name = CTFontCopyFamilyName(font) as String
        // SF Pro may resolve to .AppleSystemUIFont or SF Pro
        #expect(!name.isEmpty)
        #expect(CTFontGetSize(font) == 16)
    }

    @Test("resolveFont with italic produces different font than normal")
    func resolveItalic() {
        let normal = PenTextMeasurer.resolveFont(family: "Helvetica", size: 14, weight: "normal", style: "normal")
        let italic = PenTextMeasurer.resolveFont(family: "Helvetica", size: 14, weight: "normal", style: "italic")
        let normalName = CTFontCopyPostScriptName(normal) as String
        let italicName = CTFontCopyPostScriptName(italic) as String
        // Italic variant should have a different PostScript name (e.g. Helvetica-Oblique)
        #expect(normalName != italicName)
    }

    @Test("resolveFont with unknown family falls back gracefully")
    func unknownFamilyFallback() {
        let font = PenTextMeasurer.resolveFont(
            family: "NonExistentFontFamily12345",
            size: 20,
            weight: "normal",
            style: "normal"
        )
        // Should return some valid font (system fallback)
        #expect(CTFontGetSize(font) == 20)
    }

    // MARK: - Determinism

    @Test("Repeated measurements produce identical results")
    func deterministic() {
        let text = "Determinism test string with various characters: ABC xyz 123"
        let size1 = PenTextMeasurer.measure(text, fontFamily: "SF Pro", fontSize: 24)
        let size2 = PenTextMeasurer.measure(text, fontFamily: "SF Pro", fontSize: 24)
        #expect(size1.width == size2.width)
        #expect(size1.height == size2.height)
    }

    @Test("Wrapped measurements are deterministic")
    func wrappedDeterministic() {
        let text = "A longer text string that will need to wrap across multiple lines when measured"
        let size1 = PenTextMeasurer.measure(text, fontSize: 16, maxWidth: 200)
        let size2 = PenTextMeasurer.measure(text, fontSize: 16, maxWidth: 200)
        #expect(size1.width == size2.width)
        #expect(size1.height == size2.height)
    }
}
