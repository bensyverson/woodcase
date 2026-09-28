//
//  PenStrokeBandHitTestTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenLayoutEngine/strokeBandContains(_:of:box:)`` — the true stroked outline, not
/// ``PenLayoutEngine/ownInk(of:box:)``'s bounding rect of it — for a rect, a rounded
/// rect's corner, an ellipse, a line's caps, and each alignment.
struct PenStrokeBandHitTestTests {
    @Test("A centred stroke's band straddles the edge; well inside or outside misses")
    func rectCentered() throws {
        // 100x60 box, centred stroke 10: the band spans 95...105 across the top edge.
        let node = try Self.node(Self.rectangle(strokeWidth: 10, alignment: "center"))
        let box = PenRect(x: 0, y: 0, width: 100, height: 60)
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 0), of: node, box: box))
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 4), of: node, box: box))
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: -4), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 10), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: -10), of: node, box: box))
    }

    @Test("An outer stroke's band lies wholly outside the box; inside it misses")
    func rectOuter() throws {
        let node = try Self.node(Self.rectangle(strokeWidth: 10, alignment: "outer"))
        let box = PenRect(x: 0, y: 0, width: 100, height: 60)
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: -5), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 5), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: -15), of: node, box: box))
    }

    @Test("An inner stroke's band lies wholly inside the box; outside it misses")
    func rectInner() throws {
        let node = try Self.node(Self.rectangle(strokeWidth: 10, alignment: "inner"))
        let box = PenRect(x: 0, y: 0, width: 100, height: 60)
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 5), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: -5), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 15), of: node, box: box))
    }

    @Test("A rounded corner's band follows the true curve, not the corner's bounding box")
    func roundedRectCorner() throws {
        // 100x60 box, corner radius 20, outer stroke 10. At 45° from the corner's centre
        // (20, 20), the curve sits at radius 20 from that centre, so the outer band spans
        // radius 20...30 along the diagonal. A point at radius 25 (mid-band) hits; one at
        // radius 5 — well inside the rounded shape, but inside the corner's naive
        // *rectangular* bounding box, where the old rectangular-reach code would have
        // called it a hit — misses, and so does one past the band at radius 40.
        let node = try Self.node(Self.rectangle(strokeWidth: 10, alignment: "outer", cornerRadius: 20))
        let box = PenRect(x: 0, y: 0, width: 100, height: 60)
        let diagonal = sqrt(2.0) / 2
        func point(atRadius radius: Double) -> PenPoint {
            PenPoint(x: 20 - radius * diagonal, y: 20 - radius * diagonal)
        }
        #expect(PenLayoutEngine.strokeBandContains(point(atRadius: 25), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(point(atRadius: 5), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(point(atRadius: 40), of: node, box: box))
    }

    @Test("An ellipse's band follows its curve, not its bounding box's corner")
    func ellipse() throws {
        // 100x60 ellipse (a=50, b=30), centred stroke 10. (95, 55) sits near the bounding
        // box's corner (100, 60) — normalized radius ((45/50)^2+(25/30)^2) ≈ 1.5, well
        // outside the true curve — and must miss, though a rectangular-reach
        // approximation of the band, grown from the box, would call it a hit.
        let json = """
        {"version": "2.19", "children": [{"type": "ellipse", "id": "e", "x": 0, "y": 0,
          "width": 100, "height": 60, "fill": "#FF0000", "stroke": "#000000", "strokeWidth": 10,
          "strokeAlignment": "center"}]}
        """
        let node = try Self.node(json)
        let box = PenRect(x: 0, y: 0, width: 100, height: 60)
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 0), of: node, box: box))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 95, y: 55), of: node, box: box))
    }

    @Test("A line's band is its capsule: butt ends flush, round and square reach past it")
    func lineCaps() throws {
        func line(_ cap: String) -> String {
            """
            {"version": "2.19", "children": [{"type": "line", "id": "l", "x": 0, "y": 0,
              "width": 100, "height": 0, "stroke": "#000000", "strokeWidth": 10,
              "strokeLinecap": "\(cap)"}]}
            """
        }
        let box = PenRect(x: 0, y: 0, width: 100, height: 0)
        // Along the segment, mid-way, within the half-width: every cap hits.
        for cap in ["butt", "round", "square"] {
            let node = try Self.node(line(cap))
            #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 3), of: node, box: box), "\(cap)")
        }
        // Just past the end (x = 103): a butt cap misses, round and square reach it.
        let butt = try Self.node(line("butt"))
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 103, y: 0), of: butt, box: box))
        let round = try Self.node(line("round"))
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 103, y: 0), of: round, box: box))
        let square = try Self.node(line("square"))
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 103, y: 0), of: square, box: box))
        // Alignment plays no part for a line: an inner-aligned line still hits its centred band.
        let inner = try Self.node("""
        {"version": "2.19", "children": [{"type": "line", "id": "l", "x": 0, "y": 0,
          "width": 100, "height": 0, "stroke": "#000000", "strokeWidth": 10, "strokeAlignment": "inner"}]}
        """)
        #expect(PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 3), of: inner, box: box))
    }

    @Test("No stroke, or one with no visible paint, never hits")
    func noVisibleStroke() throws {
        let box = PenRect(x: 0, y: 0, width: 100, height: 60)
        let noStroke = try Self.node("""
        {"version": "2.19", "children": [{"type": "rectangle", "id": "r", "x": 0, "y": 0,
          "width": 100, "height": 60, "fill": "#FF0000"}]}
        """)
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 0), of: noStroke, box: box))
        let disabled = try Self.node("""
        {"version": "2.19", "children": [{"type": "rectangle", "id": "r", "x": 0, "y": 0,
          "width": 100, "height": 60, "fill": "#FF0000", "stroke": "#00FF0000", "strokeWidth": 10}]}
        """)
        #expect(!PenLayoutEngine.strokeBandContains(PenPoint(x: 50, y: 0), of: disabled, box: box))
    }

    // MARK: - Helpers

    /// A 100×60 rectangle with a uniform stroke, optionally rounded.
    private static func rectangle(strokeWidth: Double, alignment: String, cornerRadius: Double? = nil) -> String {
        let corner = cornerRadius.map { ", \"cornerRadius\": \($0)" } ?? ""
        return """
        {"version": "2.19", "children": [{"type": "rectangle", "id": "r", "x": 0, "y": 0,
          "width": 100, "height": 60, "fill": "#FF0000", "stroke": "#000000",
          "strokeWidth": \(strokeWidth), "strokeAlignment": "\(alignment)"\(corner)}]}
        """
    }

    /// Parses `json` and returns its one child node.
    private static func node(_ json: String) throws -> PenNode {
        let document = try PenParser.parse(Data(json.utf8))
        return try #require(document.children.first)
    }
}
