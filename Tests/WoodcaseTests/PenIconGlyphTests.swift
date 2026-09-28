import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Pins the public icon glyph: which glyph an icon draws, in which face and size, and
/// where in its box — the one answer Woodcase's CG renderer and RapidPro both draw from.
struct PenIconGlyphTests {
    private static let square = CGSize(width: 48, height: 48)

    private static func data(library: String?, icon: String?, weight: Double? = nil) -> PenNode.IconData {
        PenNode.IconData(
            icon: icon.map { .literal($0) },
            library: library.map { .literal($0) },
            weight: weight.map { .literal($0) }
        )
    }

    /// The face's `wght` axis value, or `nil` when the font carries no variation.
    private static func wght(of font: CTFont) -> Double? {
        let tag = 0x7767_6874 // "wght"
        guard let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber] else { return nil }
        return variation[NSNumber(value: tag)]?.doubleValue
    }

    @Test("A known icon resolves to its library's glyph, in its library's face")
    func knownIcon() throws {
        let glyph = try #require(PenIconGlyph(data: Self.data(library: "lucide", icon: "ellipsis"), box: Self.square))
        let resolved = try #require(PenIconFontRegistry.shared.resolve(family: "lucide", name: "ellipsis"))
        #expect(glyph.string.unicodeScalars.map(\.value) == [resolved.codepoint])
        #expect(CTFontCopyPostScriptName(glyph.font) as String == resolved.ctFontName)
    }

    @Test("An icon name the library does not know draws the library's placeholder glyph")
    func unknownNameDrawsPlaceholder() throws {
        let glyph = try #require(PenIconGlyph(data: Self.data(library: "lucide", icon: "no-such-icon"), box: Self.square))
        let placeholder = try #require(PenIconFontRegistry.shared.placeholder(family: "lucide"))
        #expect(glyph.string.unicodeScalars.map(\.value) == [placeholder.codepoint])
    }

    @Test(
        "No glyph without a library and an icon name, or for a library Woodcase does not know",
        arguments: [
            (String?.none, String?.some("ellipsis")),
            ("lucide", nil),
            ("no-such-library", "ellipsis"),
        ]
    )
    func noGlyph(library: String?, icon: String?) {
        #expect(PenIconGlyph(data: Self.data(library: library, icon: icon), box: Self.square) == nil)
    }

    @Test("The font size is the box's shorter side", arguments: [
        CGSize(width: 48, height: 48), CGSize(width: 64, height: 32), CGSize(width: 32, height: 64),
    ])
    func fontSizeIsShorterSide(box: CGSize) throws {
        let glyph = try #require(PenIconGlyph(data: Self.data(library: "feather", icon: "bell"), box: box))
        #expect(CTFontGetSize(glyph.font) == min(box.width, box.height))
    }

    @Test("A Material Symbols face is drawn at weight 200 when the node sets none, else at the node's")
    func materialWeight() throws {
        let unset = try #require(PenIconGlyph(
            data: Self.data(library: "Material Symbols Outlined", icon: "vpn_lock"), box: Self.square
        ))
        let set = try #require(PenIconGlyph(
            data: Self.data(library: "Material Symbols Outlined", icon: "vpn_lock", weight: 500), box: Self.square
        ))
        #expect(Self.wght(of: unset.font) == 200)
        #expect(Self.wght(of: set.font) == 500)
    }

    /// The glyph's outline bounds as fractions of the font size.
    private static func unitBounds(of glyph: PenIconGlyph) throws -> CGRect {
        let characters = Array(glyph.string.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        #expect(CTFontGetGlyphsForCharacters(glyph.font, characters, &glyphs, characters.count))
        let outline = try #require(CTFontCreatePathForGlyph(glyph.font, glyphs[0], nil))
        let size = CTFontGetSize(glyph.font)
        return outline.boundingBoxOfPath.applying(CGAffineTransform(scaleX: 1 / size, y: 1 / size))
    }

    /// Pen draws a Material Symbols glyph at the font's default optical size (`opsz` 24)
    /// whatever the icon's size, where Core Text would move the axis to the point size.
    @Test(
        "A Material Symbols glyph keeps the font's default optical size at every size",
        arguments: [16.0, 48.0, 96.0]
    )
    func materialOpticalSizeIsTheDefault(side: Double) throws {
        let box = CGSize(width: side, height: side)
        let reference = try #require(PenIconGlyph(
            library: "Material Symbols Outlined", icon: "vpn_lock", weight: nil, box: CGSize(width: 24, height: 24)
        ))
        let glyph = try #require(PenIconGlyph(
            library: "Material Symbols Outlined", icon: "vpn_lock", weight: nil, box: box
        ))
        let expected = try Self.unitBounds(of: reference)
        let actual = try Self.unitBounds(of: glyph)
        #expect(abs(actual.maxX - expected.maxX) < 1e-4, "maxX \(actual.maxX), at 24 pt \(expected.maxX)")
        #expect(abs(actual.maxY - expected.maxY) < 1e-4, "maxY \(actual.maxY), at 24 pt \(expected.maxY)")
        #expect(abs(actual.minX - expected.minX) < 1e-4, "minX \(actual.minX), at 24 pt \(expected.minX)")
    }

    @Test("A weight does not vary a face that is not Material Symbols")
    func weightIgnoredElsewhere() throws {
        let plain = try #require(PenIconGlyph(data: Self.data(library: "lucide", icon: "ellipsis"), box: Self.square))
        let weighted = try #require(PenIconGlyph(
            data: Self.data(library: "lucide", icon: "ellipsis", weight: 500), box: Self.square
        ))
        #expect(plain == weighted)
    }

    @Test("The glyph sits where Pen puts it, within a tenth of a point", arguments: PenIconPlacementTests.cases)
    func originMatchesPen(_ probe: PenIconPlacementTests.Case) throws {
        let glyph = try #require(PenIconGlyph(
            library: probe.library, icon: probe.icon, weight: nil,
            box: CGSize(width: probe.width, height: probe.height)
        ))
        #expect(abs(glyph.origin.x - probe.x) < 0.1, "x \(glyph.origin.x), Pen \(probe.x)")
        #expect(abs(glyph.origin.y - probe.baseline) < 0.1, "baseline \(glyph.origin.y), Pen \(probe.baseline)")
    }

    @Test("The data initializer reads the node's library, icon and weight")
    func dataInitializerMatchesFieldInitializer() {
        let box = CGSize(width: 64, height: 32)
        let fromData = PenIconGlyph(
            data: Self.data(library: "Material Symbols Rounded", icon: "vpn_lock", weight: 300), box: box
        )
        let fromFields = PenIconGlyph(library: "Material Symbols Rounded", icon: "vpn_lock", weight: 300, box: box)
        #expect(fromData != nil)
        #expect(fromData == fromFields)
    }
}
