import Foundation
import Testing
@testable import WoodcaseCommandCore

struct OutputNamerTests {
    @Test("Single frame PNG at default scale uses base name")
    func singleFramePNG() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: nil, format: .png, scale: 2,
            isMultiFrame: false
        )
        #expect(name == "myfile@2x.png")
    }

    @Test("Single frame at scale 1 omits scale suffix")
    func singleFrameScale1() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: nil, format: .png, scale: 1,
            isMultiFrame: false
        )
        #expect(name == "myfile.png")
    }

    @Test("Multiple frames include frame name")
    func multipleFrames() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Screen1", format: .png, scale: 2,
            isMultiFrame: true
        )
        #expect(name == "myfile-Screen1@2x.png")
    }

    @Test("Frame name with unsafe chars is sanitized")
    func sanitizedFrameName() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Screen/1", format: .png, scale: 2,
            isMultiFrame: true
        )
        #expect(name == "myfile-Screen-1@2x.png")
    }

    @Test("PDF single frame uses base name")
    func singleFramePDF() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: nil, format: .pdf, scale: 2,
            isMultiFrame: false
        )
        #expect(name == "myfile.pdf")
    }

    @Test("PDF multi-frame still uses base name (frames become pages)")
    func multiFramePDF() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: nil, format: .pdf, scale: 2,
            isMultiFrame: true
        )
        #expect(name == "myfile.pdf")
    }

    // MARK: - Theme Suffix Stripping

    @Test("Strips parenthesized theme value from frame name")
    func stripsThemeSuffix() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Home - Collection (Dark)",
            format: .png, scale: 2, isMultiFrame: true,
            activeThemeValues: ["Dark", "Light"]
        )
        #expect(name == "myfile-Home---Collection@2x.png")
    }

    @Test("Strips theme suffix regardless of case")
    func stripsThemeSuffixCaseInsensitive() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Screen (dark)",
            format: .png, scale: 2, isMultiFrame: true,
            activeThemeValues: ["dark"]
        )
        #expect(name == "myfile-Screen@2x.png")
    }

    @Test("Does not strip when no theme values provided")
    func noStrippingWithoutThemeValues() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Screen (Dark)",
            format: .png, scale: 2, isMultiFrame: true
        )
        #expect(name == "myfile-Screen-(Dark)@2x.png")
    }

    @Test("Strips trailing whitespace after removing theme suffix")
    func stripsTrailingWhitespace() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Ratings (Light)",
            format: .png, scale: 2, isMultiFrame: true,
            activeThemeValues: ["Light"]
        )
        #expect(name == "myfile-Ratings@2x.png")
    }

    @Test("Handles multiple theme values across axes")
    func multiAxisThemeStripping() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Dashboard (Dark) (Mobile)",
            format: .png, scale: 2, isMultiFrame: true,
            activeThemeValues: ["Dark", "Mobile"]
        )
        #expect(name == "myfile-Dashboard@2x.png")
    }

    @Test("Preserves parenthesized text that is not a theme value")
    func preservesNonThemeParentheses() {
        let name = OutputNamer.filename(
            baseName: "myfile", frameName: "Home (v2) (Dark)",
            format: .png, scale: 2, isMultiFrame: true,
            activeThemeValues: ["Dark"]
        )
        #expect(name == "myfile-Home-(v2)@2x.png")
    }
}
