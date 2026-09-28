//
//  PenIconPlacementTests.swift
//  WoodcaseTests
//

import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Pins where an icon's glyph sits in its box: where Pen puts it, by the font's metrics,
/// not by the glyph's ink.
///
/// `render-icon-placement.pen` has one artboard per bundled library (`lucide`, `feather`,
/// `phosphor`, and the three Material Symbols styles), each drawing two glyphs in four
/// boxes: 24 × 24, 48 × 48, 64 × 32 and 32 × 64. The references are Pen's 2x PNG exports
/// (`scripts/pen-oracle Tests/WoodcaseTests/Fixtures/render-icon-placement.pen --scale 2`,
/// pen CLI 0.3.9, 2026-09-27). The glyph origins below are Pen's, fitted from those
/// exports by `xcrun swift scripts/icon-placement-fit.swift
/// Tests/WoodcaseTests/Fixtures/render-icon-placement.pen` to a thirty-second of a point.
struct PenIconPlacementTests {
    private static let fixture = "render-icon-placement"
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Every artboard, in document order.
    private static let artboards = ["lucide", "feather", "phosphor", "outlined", "rounded", "sharp"]

    /// A glyph in a box, and where Pen put its origin: the pen position across and the
    /// baseline down from the box's top-left, in points.
    struct Case: CustomTestStringConvertible {
        var library: String
        var icon: String
        var width: Double
        var height: Double
        var x: Double
        var baseline: Double

        var testDescription: String {
            "\(library) \(icon) \(Int(width))x\(Int(height))"
        }
    }

    /// Pen's fitted origins, one glyph per library, at two sizes and in both non-square boxes.
    static let cases: [Case] = [
        Case(library: "lucide", icon: "ellipsis", width: 24, height: 24, x: 0, baseline: 24.01),
        Case(library: "lucide", icon: "ellipsis", width: 48, height: 48, x: 0, baseline: 48.00),
        Case(library: "lucide", icon: "ellipsis", width: 64, height: 32, x: 16, baseline: 32.00),
        Case(library: "lucide", icon: "ellipsis", width: 32, height: 64, x: 0, baseline: 48.00),
        Case(library: "feather", icon: "bell", width: 24, height: 24, x: 0, baseline: 22.27),
        Case(library: "feather", icon: "bell", width: 48, height: 48, x: 0, baseline: 44.58),
        Case(library: "feather", icon: "chevron-down", width: 64, height: 32, x: 16, baseline: 29.70),
        Case(library: "feather", icon: "chevron-down", width: 32, height: 64, x: 0, baseline: 45.70),
        Case(library: "phosphor", icon: "chat-dots-thin", width: 24, height: 24, x: 0, baseline: 24.01),
        Case(library: "phosphor", icon: "chat-dots-thin", width: 48, height: 48, x: 0, baseline: 48.00),
        Case(library: "phosphor", icon: "chat-dots-thin", width: 64, height: 32, x: 16, baseline: 32.00),
        Case(library: "phosphor", icon: "chat-dots-thin", width: 32, height: 64, x: 0, baseline: 48.00),
        Case(library: "Material Symbols Outlined", icon: "vpn_lock", width: 24, height: 24, x: 0.02, baseline: 23.99),
        Case(library: "Material Symbols Rounded", icon: "vpn_lock", width: 48, height: 48, x: 0.01, baseline: 47.99),
        Case(library: "Material Symbols Sharp", icon: "vpn_lock", width: 64, height: 32, x: 16, baseline: 32.01),
        Case(library: "Material Symbols Outlined", icon: "keyboard_arrow_down", width: 32, height: 64, x: 0, baseline: 47.97),
    ]

    @Test("The case list names every artboard of the fixture")
    func caseListIsComplete() throws {
        let names = try PenSnapshotTestHelpers.artboardNames(in: Self.fixture, fixturesDir: Self.fixturesDir)
        #expect(names == Self.artboards)
    }

    @Test("The glyph origin is where Pen puts it, within a tenth of a point", arguments: cases)
    func originMatchesPen(_ probe: Case) throws {
        let registry = PenIconFontRegistry.shared
        let icon = try #require(registry.resolve(family: probe.library, name: probe.icon))
        let size = min(probe.width, probe.height)
        let font = PenIconFontRenderer.font(for: icon, size: CGFloat(size), weight: nil, family: probe.library)
        let origin = PenIconFontRenderer.glyphOrigin(
            font: font, codepoint: icon.codepoint, box: CGSize(width: probe.width, height: probe.height)
        )
        #expect(abs(origin.x - probe.x) < 0.1, "x \(origin.x), Pen \(probe.x)")
        #expect(abs(origin.y - probe.baseline) < 0.1, "baseline \(origin.y), Pen \(probe.baseline)")
    }

    @Test("Each library's board matches Pen's render within MAE 1.21", arguments: artboards)
    func matchesPen(artboard: String) throws {
        let document = try PenParser.parse(
            contentsOf: Self.fixturesDir.appendingPathComponent("\(Self.fixture).pen")
        )
        let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document))
        let rects = PenLayoutEngine.layout(resolved)
        let root = try #require(resolved.children.first { $0.common.name == artboard })
        let rect = try #require(rects[root.id])
        let rendered = try #require(PenRenderer.render(
            resolved, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
            scale: 2, rootNodeID: root.id
        ))
        let reference = try #require(PenSnapshotTestHelpers.loadFixtureImage(
            named: "\(Self.fixture)-\(artboard)", fixturesDir: Self.fixturesDir
        ))
        #expect(rendered.width == reference.width && rendered.height == reference.height)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: rendered, and: reference)
        print("Icon placement \(artboard) MAE: \(mae)")
        // max(measured×1.5, measured+0.25) over the worst case (`phosphor`, 0.804; the others 0.62–0.79,
        // swift test -j 3 --filter PenIconPlacementTests, 2026-09-27, leaf 6vLFNQ). The Material boards
        // scored 0.86–0.88 while Core Text drew them in the optical cut of their point size, where Pen
        // keeps the font's default (PenIconFonts.md, "Which cut of the glyph"); what is left is rasterisation.
        #expect(mae < 1.21, "\(artboard): MAE \(mae)")
    }
}
