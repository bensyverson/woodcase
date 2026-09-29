//
//  PenPaintedExtentTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenLayoutEngine/paintedExtent(of:rect:layoutRects:)`` — extent (iii), what may
/// carry ink — rule by rule against Pen's `getVisualLocalBounds`
/// (`project/2026-09-28-geometry-model.md`, "Pen's own code"). The Pen exports that
/// confirm the rules are in ``PenPaintedExtentProbeTests``.
struct PenPaintedExtentTests {
    /// A 100×60 rectangle at `(10, 20)` carrying `keys`, alone in a document.
    private static func rectangle(_ keys: String) -> String {
        """
        {"version": "2.19", "children": [{"type": "rectangle", "id": "r", "x": 10, "y": 20,
          "width": 100, "height": 60, "fill": "#FF0000"\(keys.isEmpty ? "" : ", " + keys)}]}
        """
    }

    @Test("A plain node's painted extent is its bounds")
    func plainNode() throws {
        #expect(try Self.extent(Self.rectangle(""), "r") == PenRect(x: 10, y: 20, width: 100, height: 60))
    }

    @Test("An inner stroke adds nothing, a centered one half its width, an outer one all of it")
    func strokeAlignment() throws {
        let stroke = ##""stroke": "#00FF00", "strokeWidth": 12"##
        #expect(try Self.extent(Self.rectangle(stroke + ##", "strokeAlignment": "inner""##), "r")
            == PenRect(x: 10, y: 20, width: 100, height: 60))
        #expect(try Self.extent(Self.rectangle(stroke), "r") == PenRect(x: 4, y: 14, width: 112, height: 72))
        #expect(try Self.extent(Self.rectangle(stroke + ##", "strokeAlignment": "outer""##), "r")
            == PenRect(x: -2, y: 8, width: 124, height: 84))
    }

    @Test("A per-side stroke widens each side by its own width; a missing side by none")
    func perSideStroke() throws {
        let keys = ##""stroke": "#00FF00", "strokeAlignment": "outer", "strokeWidth": {"top": 4, "right": 16, "left": 8}"##
        #expect(try Self.extent(Self.rectangle(keys), "r") == PenRect(x: 2, y: 16, width: 124, height: 64))
    }

    @Test("A stroke with no paint that shows adds nothing")
    func invisibleStroke() throws {
        let keys = ##""stroke": "#00FF0000", "strokeWidth": 12, "strokeAlignment": "outer""##
        #expect(try Self.extent(Self.rectangle(keys), "r") == PenRect(x: 10, y: 20, width: 100, height: 60))
    }

    @Test("An outer shadow adds its offset copy of the extent grown by 1.5 × blur; an inner shadow adds nothing")
    func shadows() throws {
        let outer = ##""effect": {"type": "shadow", "offset": {"x": 10, "y": -6}, "blur": 8, "color": "#00000080"}"##
        #expect(try Self.extent(Self.rectangle(outer), "r") == PenRect(x: 8, y: 2, width: 124, height: 84))
        let inner = ##""effect": {"type": "shadow", "shadowType": "inner", "offset": {"x": 10, "y": 10}, "blur": 8, "color": "#000000"}"##
        #expect(try Self.extent(Self.rectangle(inner), "r") == PenRect(x: 10, y: 20, width: 100, height: 60))
        let disabled = ##""effect": {"type": "shadow", "enabled": false, "offset": {"x": 10, "y": 10}, "blur": 8, "color": "#000000"}"##
        #expect(try Self.extent(Self.rectangle(disabled), "r") == PenRect(x: 10, y: 20, width: 100, height: 60))
    }

    @Test("Every shadow copies the extent before any shadow; a layer blur then grows the whole by 1.5 × radius")
    func shadowsThenBlur() throws {
        let keys = """
        "effect": [
          {"type": "shadow", "offset": {"x": 20, "y": 0}, "blur": 0, "color": "#000000"},
          {"type": "shadow", "offset": {"x": 0, "y": 20}, "blur": 0, "color": "#000000"},
          {"type": "blur", "radius": 4}
        ]
        """
        // Shadows reach x 130 and y 100; the blur then adds 6 on every side.
        #expect(try Self.extent(Self.rectangle(keys), "r") == PenRect(x: 4, y: 14, width: 132, height: 92))
    }

    @Test("A background blur adds nothing")
    func backgroundBlur() throws {
        let keys = ##""effect": {"type": "background_blur", "radius": 10}"##
        #expect(try Self.extent(Self.rectangle(keys), "r") == PenRect(x: 10, y: 20, width: 100, height: 60))
    }

    @Test("A text's painted extent is its glyph ink, not its box, when the ink overflows it")
    func textInkOverflowsTheBox() throws {
        let json = """
        {"version": "2.19", "children": [{"type": "text", "id": "t", "x": 10, "y": 20,
          "width": 40, "height": 15, "textGrowth": "fixed-width-height", "fontSize": 60,
          "content": "Wgpqy", "fill": "#000000"}]}
        """
        // A 60 pt line does not fit a 15 pt box on its own — SF Pro (no fontFamily, so no
        // network fetch), whose exact glyph metrics are not pinned here; only that the ink
        // reaches well past the declared box is, which any reasonable font satisfies.
        let box = PenRect(x: 10, y: 20, width: 40, height: 15)
        let got = try Self.extent(json, "t")
        #expect(got != box, "\(got)")
        #expect(got.height > box.height * 2, "\(got)")
    }

    @Test("A text with no content keeps its box — there is nothing Pen would paint differently")
    func emptyTextKeepsItsBox() throws {
        let json = """
        {"version": "2.19", "children": [{"type": "text", "id": "t", "x": 10, "y": 20,
          "width": 40, "height": 15, "fill": "#000000"}]}
        """
        #expect(try Self.extent(json, "t") == PenRect(x: 10, y: 20, width: 40, height: 15))
    }

    @Test("A turned node's band is mapped corner by corner, so its mitered corners reach past its bounds")
    func turnedBand() throws {
        let keys = ##""stroke": "#00FF00", "strokeWidth": 12, "strokeAlignment": "outer", "rotation": 90"##
        // 124×84 band about the anchor (10, 20), turned 90° counter-clockwise: x ↦ y, y ↦ −x.
        let got = try Self.extent(Self.rectangle(keys), "r")
        #expect(Self.close(got, PenRect(x: -2, y: -92, width: 84, height: 124)), "\(got)")
    }

    @Test("An unclipped frame's extent reaches its children's; a clipping frame keeps only its own")
    func frameChildren() throws {
        func frame(clip: Bool) -> String {
            """
            {"version": "2.19", "children": [{"type": "frame", "id": "f", "x": 0, "y": 0, "width": 100,
              "height": 100, "layout": "none", "clip": \(clip), "children": [
                {"type": "rectangle", "id": "c", "x": 80, "y": -10, "width": 40, "height": 20, "fill": "#000000",
                 "stroke": "#00FF00", "strokeWidth": 4, "strokeAlignment": "outer"},
                {"type": "rectangle", "id": "off", "x": -500, "y": 0, "width": 10, "height": 10, "enabled": false}
              ]}]}
            """
        }
        #expect(try Self.extent(frame(clip: false), "f") == PenRect(x: 0, y: -14, width: 124, height: 114))
        #expect(try Self.extent(frame(clip: true), "f") == PenRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test("A group's extent is its children's, and its own shadow copies that")
    func groupExtent() throws {
        let json = """
        {"version": "2.19", "children": [{"type": "group", "id": "g", "x": 50, "y": 50,
          "effect": {"type": "shadow", "offset": {"x": 0, "y": 10}, "blur": 0, "color": "#000000"}, "children": [
            {"type": "rectangle", "id": "a", "x": -20, "y": 0, "width": 20, "height": 20, "fill": "#000000"},
            {"type": "rectangle", "id": "b", "x": 30, "y": 0, "width": 20, "height": 20, "fill": "#000000",
             "effect": {"type": "blur", "radius": 4}}
          ]}]}
        """
        // a: 30…50; b blurred: 74…106 across, 44…76 down; the shadow copies it all 10 lower.
        #expect(try Self.extent(json, "g") == PenRect(x: 30, y: 44, width: 76, height: 42))
    }

    @Test("A path's geometry counts where its viewBox carries it outside the box")
    func pathOverflow() throws {
        let json = """
        {"version": "2.19", "children": [{"type": "path", "id": "p", "x": 0, "y": 100, "width": 200,
          "height": 200, "geometry": "M10 10l80 0-40 80z", "viewBox": [25, 25, 50, 50], "fill": "#00AA00"}]}
        """
        // The viewBox scales by 4 from (25, 25): the triangle spans −60…260 across, −60…260 down.
        #expect(try Self.extent(json, "p") == PenRect(x: -60, y: 40, width: 320, height: 320))
    }

    @Test("A nested node answers in its parent's coordinates")
    func nestedNode() throws {
        let json = """
        {"version": "2.19", "children": [{"type": "frame", "id": "f", "x": 300, "y": 300, "width": 100,
          "height": 100, "layout": "none", "children": [
            {"type": "rectangle", "id": "c", "x": 10, "y": 10, "width": 20, "height": 20, "fill": "#000000",
             "effect": {"type": "blur", "radius": 2}}
          ]}]}
        """
        #expect(try Self.extent(json, "c") == PenRect(x: 7, y: 7, width: 26, height: 26))
        let document = try PenParser.parse(Data(json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let canvas = try #require(PenLayoutEngine.canvasPaintedExtent(of: "c", in: document, layoutRects: rects))
        #expect(canvas == PenRect(x: 307, y: 307, width: 26, height: 26))
        #expect(PenLayoutEngine.canvasPaintedExtent(of: "nope", in: document, layoutRects: rects) == nil)
    }

    @Test("A line's band has its caps: butt ends flush, square and round ends half a width beyond")
    func lineCaps() throws {
        func line(_ cap: String) -> String {
            """
            {"version": "2.19", "children": [{"type": "line", "id": "l", "x": 0, "y": 50, "width": 100,
              "height": 0, "stroke": "#000000", "strokeWidth": 10, "strokeLinecap": "\(cap)"}]}
            """
        }
        #expect(try Self.extent(line("butt"), "l") == PenRect(x: 0, y: 45, width: 100, height: 10))
        #expect(try Self.extent(line("square"), "l") == PenRect(x: -5, y: 45, width: 110, height: 10))
        #expect(try Self.extent(line("round"), "l") == PenRect(x: -5, y: 45, width: 110, height: 10))
    }

    /// A triangle inscribed in a 100×100 box: apex (50, 0), base corners (50 ± 43.30, 75).
    /// A 10 pt outer band miters each 60° corner to 20 pt out along its bisector, and
    /// bevels it to the edges' offset ends.
    @Test("A sharp polygon's band counts its miters, or its bevels")
    func polygonJoins() throws {
        func triangle(_ join: String) -> String {
            """
            {"version": "2.19", "children": [{"type": "polygon", "id": "t", "x": 0, "y": 0, "width": 100,
              "height": 100, "polygonCount": 3, "fill": "#FF0000", "stroke": "#000000", "strokeWidth": 10,
              "strokeAlignment": "outer", "strokeLinejoin": "\(join)"}]}
            """
        }
        let half = 50 * sin(Double.pi / 3)
        let miter = try Self.extent(triangle("miter"), "t")
        let miterX = 50 + half + 20 * cos(Double.pi / 6)
        #expect(Self.close(miter, PenRect(x: 100 - miterX, y: -20, width: 2 * miterX - 100, height: 105)), "\(miter)")
        let bevel = try Self.extent(triangle("bevel"), "t")
        let bevelX = 50 + half + 10 * cos(Double.pi / 6)
        #expect(Self.close(bevel, PenRect(x: 100 - bevelX, y: -5, width: 2 * bevelX - 100, height: 90)), "\(bevel)")
    }

    @Test("Growing to whole pixels keeps the corner, rounds the size up, and ignores floating-point noise")
    func wholePixels() {
        let rect = PenRect(x: 0.25, y: -0.25, width: 1.2, height: 1)
        #expect(rect.grownToWholePixels(at: 2) == PenRect(x: 0.25, y: -0.25, width: 1.5, height: 1))
        let noisy = PenRect(x: 0.1, y: 0, width: 0.1 + 0.2, height: 1)
        #expect(noisy.grownToWholePixels(at: 10) == PenRect(x: 0.1, y: 0, width: 0.3, height: 1))
        #expect(rect.grownToWholePixels(at: 0) == rect)
    }

    // MARK: - Helpers

    /// The painted extent of `id` in `json`, in its parent's coordinates.
    private static func extent(_ json: String, _ id: String) throws -> PenRect {
        let document = try PenParser.parse(Data(json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let node = try #require(PenLayoutEngine.node(id: id, in: document.children))
        let rect = try #require(rects[id])
        return PenLayoutEngine.paintedExtent(of: node, rect: rect, layoutRects: rects)
    }

    private static func close(_ lhs: PenRect, _ rhs: PenRect) -> Bool {
        abs(lhs.x - rhs.x) < 1e-9 && abs(lhs.y - rhs.y) < 1e-9
            && abs(lhs.width - rhs.width) < 1e-9 && abs(lhs.height - rhs.height) < 1e-9
    }
}
