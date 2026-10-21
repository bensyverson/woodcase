//
//  PenRendererPaintIsolationTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A paint's blend mode blends only within its node's own paint stack — fills, then
/// strokes — drawn as an isolated group; only the node's own blend mode reaches the
/// backdrop (Ben's "reading 1" ruling, 2026-10-20; Penumbra
/// `project/2026-10-14-feature-enhancements-plan.md` §5 item 11). That is CSS's model:
/// `background-blend-mode` isolates, `mix-blend-mode` reaches the backdrop.
///
/// It departs from Pen on purpose. `paint-blend.pen` is Penumbra's session-40 evidence
/// file (`project/fixtures/session-40/`), copied unchanged, with Pen's preview beside it:
/// the pen CLI draws rectangle `a` — a lone blue fill at multiply over red — black, where
/// reading 1 draws it blue; rectangle `b` — yellow, then blue at multiply — is black in
/// both; rectangle `c` — blue with a node blend of multiply — Pen draws blue (it has no node
/// blend), Woodcase black.
struct PenRendererPaintIsolationTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// Renders the first top-level frame of `json` at 1x.
    private static func render(_ json: String) throws -> PixelGrid {
        try render(PenParser.parse(Data(json.utf8)))
    }

    /// Renders the first top-level frame of `document` at 1x.
    static func render(_ document: PenDocument) throws -> PixelGrid {
        let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document))
        let root = try #require(resolved.children.first)
        let rects = PenLayoutEngine.layout(resolved)
        let rect = try #require(rects[root.id])
        let image = try #require(PenRenderer.render(
            resolved, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height),
            scale: 1, rootNodeID: root.id
        ))
        return try #require(PixelGrid(image))
    }

    /// The session-40 evidence file, parsed.
    static func fixture() throws -> PenDocument {
        try PenParser.parse(Data(contentsOf: fixturesDir.appendingPathComponent("paint-blend.pen")))
    }

    /// A 40×40 white board with a red square under `node`, which sits at 10, 10, 20×20.
    private static func board(_ node: String) -> String {
        """
        {"version": "2.20", "children": [
          {"type": "frame", "id": "bg", "x": 0, "y": 0, "width": 40, "height": 40, "fill": "#FFFFFF",
           "layout": "none", "children": [
            {"type": "rectangle", "id": "red", "x": 0, "y": 0, "width": 40, "height": 40, "fill": "#FF0000"},
            \(node)
          ]}
        ]}
        """
    }

    private static func expectColor(
        _ pixel: PixelGrid.RGBA, _ hex: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let expected = PenHexColor(hex)!
        let close = abs(pixel.r - Int(expected.red)) <= 1 && abs(pixel.g - Int(expected.green)) <= 1
            && abs(pixel.b - Int(expected.blue)) <= 1 && abs(pixel.a - 255) <= 1
        #expect(close, "got \(pixel), expected \(hex)", sourceLocation: sourceLocation)
    }

    // MARK: - The ruling's two cases

    @Test func `A lone blue fill at multiply over red draws blue`() throws {
        let grid = try Self.render(Self.fixture())
        Self.expectColor(grid.pixel(70, 60), "#0000FF")
    }

    @Test func `Yellow, then blue at multiply, draws black over red`() throws {
        let grid = try Self.render(Self.fixture())
        Self.expectColor(grid.pixel(150, 60), "#000000")
    }

    // MARK: - Beyond the two cases

    /// Soft light composites per pixel (`PenBlendLayer`); it isolates the same way.
    @Test func `A lone fill at a per-pixel mode draws its own color`() throws {
        let grid = try Self.render(Self.board("""
        {"type": "rectangle", "id": "a", "x": 10, "y": 10, "width": 20, "height": 20,
         "fill": {"type": "color", "color": "#3366FF", "blendMode": "softLight"}}
        """))
        Self.expectColor(grid.pixel(20, 20), "#3366FF")
    }

    /// Soft light over a 40% fill beneath it, as over a translucent backdrop: #7576D1
    /// (`PenRendererBlendTests`) — the red behind the node shows through neither paint.
    @Test func `A per-pixel fill blends with the fill beneath it, not the backdrop`() throws {
        let grid = try Self.render(Self.board("""
        {"type": "rectangle", "id": "a", "x": 10, "y": 10, "width": 20, "height": 20,
         "fill": [{"type": "color", "color": "#E6994D66"}, {"type": "color", "color": "#3366FF", "blendMode": "softLight"}]}
        """))
        Self.expectColor(grid.pixel(20, 20), "#7576D1")
    }

    @Test func `A stroke-only node's multiply stroke draws its own color`() throws {
        let grid = try Self.render(Self.board("""
        {"type": "rectangle", "id": "a", "x": 10, "y": 10, "width": 20, "height": 20,
         "stroke": {"type": "color", "color": "#0000FF", "blendMode": "multiply"}, "strokeWidth": 10, "strokeAlignment": "inner"}
        """))
        Self.expectColor(grid.pixel(20, 20), "#0000FF")
    }

    /// The stroke is in the stack, above the fills: blue at multiply over yellow is black
    /// inside, and outside the box, where no fill lies beneath, the stroke is its own blue.
    @Test func `A multiply stroke blends with the fills beneath it, and only them`() throws {
        let grid = try Self.render(Self.board("""
        {"type": "rectangle", "id": "a", "x": 10, "y": 10, "width": 20, "height": 20, "fill": "#FFFF00",
         "stroke": {"type": "color", "color": "#0000FF", "blendMode": "multiply"}, "strokeWidth": 8, "strokeAlignment": "center"}
        """))
        Self.expectColor(grid.pixel(12, 20), "#000000")
        Self.expectColor(grid.pixel(7, 20), "#0000FF")
        Self.expectColor(grid.pixel(20, 20), "#FFFF00")
    }

    /// A node's outer shadow lies beneath its paints but is no paint: the fill does not
    /// blend with it.
    @Test func `A blended fill does not blend with its node's own outer shadow`() throws {
        let grid = try Self.render(Self.board("""
        {"type": "rectangle", "id": "a", "x": 10, "y": 10, "width": 20, "height": 20,
         "fill": {"type": "color", "color": "#0000FF", "blendMode": "screen"},
         "effect": {"type": "shadow", "shadowType": "outer", "offset": {"x": 0, "y": 0}, "blur": 0,
                    "color": "#00FF00"}}
        """))
        Self.expectColor(grid.pixel(20, 20), "#0000FF")
    }

    /// A child draws over its parent's paint stack, after it, and is not part of it.
    @Test func `A child's blended fill does not blend with its parent's fills`() throws {
        let grid = try Self.render(Self.board("""
        {"type": "frame", "id": "p", "x": 10, "y": 10, "width": 20, "height": 20, "fill": "#FFFF00", "layout": "none",
         "children": [{"type": "rectangle", "id": "c", "x": 0, "y": 0, "width": 20, "height": 20,
                       "fill": {"type": "color", "color": "#0000FF", "blendMode": "multiply"}}]}
        """))
        Self.expectColor(grid.pixel(20, 20), "#0000FF")
    }

    /// A text node's glyph paint isolates too: blue glyphs at multiply and at screen over red
    /// — black and magenta were they to reach the backdrop — draw the same blue. (A blended
    /// solid takes the glyph-outline route, which places glyphs a little differently from
    /// Core Text's own drawing of a normal solid, so the two blends are compared, not a blend
    /// with no blend.)
    @Test func `A text node's blended fill blends with nothing behind it`() throws {
        func text(_ mode: String) -> String {
            """
            {"type": "text", "id": "t", "x": 2, "y": 2, "content": "M", "fontSize": 30, "fontFamily": "Inter",
             "fill": {"type": "color", "color": "#0000FF", "blendMode": "\(mode)"}}
            """
        }
        TestFontRegistration.registerTestFonts()
        let multiply = try Self.render(Self.board(text("multiply")))
        let screen = try Self.render(Self.board(text("screen")))
        var differing = 0
        var blue = 0
        for y in 0 ..< multiply.height {
            for x in 0 ..< multiply.width {
                if multiply.pixel(x, y) != screen.pixel(x, y) { differing += 1 }
                if multiply.pixel(x, y) == PixelGrid.RGBA(r: 0, g: 0, b: 255, a: 255) { blue += 1 }
            }
        }
        #expect(differing == 0)
        #expect(blue > 20)
    }
}
