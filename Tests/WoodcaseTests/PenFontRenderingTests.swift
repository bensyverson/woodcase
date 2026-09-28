import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Tests that bundled test fonts are correctly registered with Core Text
/// and produce accurate text measurements distinct from the SF Pro fallback.
struct PenFontRenderingTests {
    init() {
        TestFontRegistration.registerTestFonts()
        // Trigger auto-registration of bundled icon fonts (lucide is now in the library, not test fonts)
        _ = PenIconFontRegistry.shared.codepoint(family: "lucide", name: "bell")
    }

    // MARK: - Font Availability

    @Test("IBM Plex Sans is available after registration")
    func ibmPlexSansAvailable() {
        let font = PenTextMeasurer.resolveFont(
            family: "IBM Plex Sans",
            size: 16,
            weight: "normal",
            style: "normal"
        )
        let familyName = CTFontCopyFamilyName(font) as String
        #expect(familyName == "IBM Plex Sans")
    }

    @Test("IBM Plex Sans Medium weight resolves correctly")
    func ibmPlexSansMedium() {
        let font = PenTextMeasurer.resolveFont(
            family: "IBM Plex Sans",
            size: 16,
            weight: "500",
            style: "normal"
        )
        let familyName = CTFontCopyFamilyName(font) as String
        #expect(familyName == "IBM Plex Sans")
    }

    @Test("IBM Plex Sans SemiBold weight resolves correctly")
    func ibmPlexSansSemiBold() {
        let font = PenTextMeasurer.resolveFont(
            family: "IBM Plex Sans",
            size: 16,
            weight: "600",
            style: "normal"
        )
        let familyName = CTFontCopyFamilyName(font) as String
        #expect(familyName == "IBM Plex Sans")
    }

    /// Pen draws IBM Plex Sans from Google's variable face (wdth 75–100, wght 100–700),
    /// not the static cuts, whose outlines are an older release
    /// (`project/2026-09-28-pen-font-faces.md`); each weight is its own instance.
    @Test("The registered IBM Plex Sans is Google's variable face, each weight its own instance", arguments: [400, 500, 600])
    func ibmPlexSansIsTheVariableFace(weight: Int) throws {
        let font = PenTextMeasurer.resolveFont(family: "IBM Plex Sans", size: 16, weight: "\(weight)", style: "normal")
        let axes = try #require(CTFontCopyVariationAxes(font) as? [[CFString: Any]], "no variation axes: a static cut")
        let tags = Set(axes.compactMap { $0[kCTFontVariationAxisIdentifierKey] as? Int })
        #expect(tags == [0x7767_6874, 0x7764_7468], "axes \(tags): expected wght and wdth")
        let variation = try #require(CTFontCopyVariation(font) as? [Int: Double], "no variation applied")
        // Core Text leaves an axis at its default out of the variation it reports.
        #expect(variation[0x7767_6874, default: 400] == Double(weight))
    }

    @Test("Lucide icon font is available after registration")
    func lucideAvailable() {
        let font = PenTextMeasurer.resolveFont(
            family: "lucide",
            size: 18,
            weight: "normal",
            style: "normal"
        )
        let familyName = CTFontCopyFamilyName(font) as String
        #expect(familyName == "lucide")
    }

    // MARK: - Measurement Accuracy

    @Test("IBM Plex Sans measurements differ from SF Pro")
    func plexMeasurementsDifferFromFallback() {
        let text = "Woodcase"

        let plexSize = PenTextMeasurer.measure(
            text,
            fontFamily: "IBM Plex Sans",
            fontSize: 36,
            fontWeight: "600",
            letterSpacing: -0.5
        )

        let sfProSize = PenTextMeasurer.measure(
            text,
            fontFamily: "SF Pro",
            fontSize: 36,
            fontWeight: "600",
            letterSpacing: -0.5
        )

        // Different fonts should produce different measurements
        #expect(plexSize.width != sfProSize.width || plexSize.height != sfProSize.height)
        // Both should be non-zero
        #expect(plexSize.width > 0)
        #expect(plexSize.height > 0)
    }

    @Test("IBM Plex Sans weight variants produce different widths")
    func weightVariantsProduceDifferentWidths() {
        let text = "Usage Log"

        let regularWidth = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 14, fontWeight: "normal"
        ).width
        let mediumWidth = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 14, fontWeight: "500"
        ).width
        let semiBoldWidth = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 14, fontWeight: "600"
        ).width

        // All should be non-zero
        #expect(regularWidth > 0)
        #expect(mediumWidth > 0)
        #expect(semiBoldWidth > 0)

        // Heavier weights are typically wider
        #expect(semiBoldWidth >= regularWidth)
    }

    @Test("Variable-bound text fills resolve correctly for dark theme")
    func darkThemeFillResolution() throws {
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let penURL = fixturesDir.appendingPathComponent("woodcase-app.pen")
        let penData = try Data(contentsOf: penURL)
        let parsed = try PenParser.parse(penData)
        let expanded = PenRefExpander.expand(parsed)
        let resolved = PenVariableResolver.resolve(expanded, theme: ["mode": "dark"])

        /// Find "appTitle" text node in the expanded tree
        func findNode(_ nodes: [PenNode], name: String) -> PenNode? {
            for node in nodes {
                if node.common.name == name { return node }
                if case let .frame(data) = node.kind, let children = data.children {
                    if let found = findNode(children, name: name) { return found }
                }
                if case let .group(data) = node.kind, let children = data.children {
                    if let found = findNode(children, name: name) { return found }
                }
            }
            return nil
        }

        let appTitle = try #require(findNode(resolved.children, name: "appTitle"))
        guard case let .text(data) = appTitle.kind else {
            Issue.record("Expected text node")
            return
        }
        // After resolution with dark theme and expansion, fill should be #F5F2EC
        guard case let .single(.shorthand(hex)) = data.fills else {
            Issue.record("Expected single shorthand fill, got: \(String(describing: data.fills))")
            return
        }
        #expect(hex == "#F5F2EC", "Expected dark text-primary color, got \(hex)")
    }

    @Test("IBM Plex Sans line height multiplier works correctly")
    func lineHeightMultiplier() {
        let text = "Line one\nLine two"

        let defaultHeight = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 16
        ).height

        let tightHeight = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 16, lineHeight: 1.05
        ).height

        let looseHeight = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 16, lineHeight: 1.8
        ).height

        #expect(tightHeight < looseHeight)
        #expect(defaultHeight > 0)
    }

    @Test("IBM Plex Sans letter spacing affects width")
    func letterSpacingAffectsWidth() {
        let text = "Ratings"

        let normalWidth = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 36, fontWeight: "600"
        ).width

        let tightWidth = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 36, fontWeight: "600",
            letterSpacing: -0.5
        ).width

        let wideWidth = PenTextMeasurer.measure(
            text, fontFamily: "IBM Plex Sans", fontSize: 36, fontWeight: "600",
            letterSpacing: 2.0
        ).width

        #expect(tightWidth < normalWidth)
        #expect(wideWidth > normalWidth)
    }
}
