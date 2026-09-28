//
//  DisclosureGlyphTests.swift
//  WoodcaseViewerTests
//

import Elementary
import Testing
@testable import WoodcaseViewer

/// The shared disclosure triangle: one SVG shape, reused by any expand/collapse control.
struct DisclosureGlyphTests {
    @Test("The glyph is inline SVG, not a text character — every user agent draws the same shape")
    func rendersAsInlineSVG() {
        let html = DisclosureGlyph().render()
        #expect(html.contains("<svg"))
        #expect(!html.contains("▾"))
        #expect(!html.contains("▸"))
    }

    @Test("The glyph carries only its own shared class, free of any panel's styling")
    func carriesOnlyItsOwnClass() {
        let html = DisclosureGlyph().render()
        #expect(html.contains("class=\"v-disclosure-glyph\""))
        #expect(!html.contains("v-variable"))
        #expect(!html.contains("v-outline"))
    }

    @Test("The glyph is decorative — its caller supplies the accessible label")
    func isHiddenFromAssistiveTech() {
        let html = DisclosureGlyph().render()
        #expect(html.contains("aria-hidden=\"true\""))
    }
}
