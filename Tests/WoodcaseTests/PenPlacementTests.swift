//
//  PenPlacementTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenPlacement`` — extent (ii), a node's box and the map that carries it into its
/// parent's (or the canvas's) coordinates — against Pen's own composition, written out
/// independently here: `translate(x, y) · turn(θ counter-clockwise) · flip` about each
/// node's anchor, a group's children measured from its anchor
/// (`project/2026-09-28-geometry-model.md`, "Pen's own code").
struct PenPlacementTests {
    /// A board holding a group turned −40° about its anchor, whose second child is turned
    /// 30° and flipped vertically about its own.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "B", "x": 100, "y": 50, "width": 600, "height": 400, "layout": "none", "children": [
          { "type": "group", "id": "G", "x": 200, "y": 150, "rotation": -40, "children": [
            { "type": "rectangle", "id": "A", "x": -20, "y": -10, "width": 30, "height": 16 },
            { "type": "rectangle", "id": "T", "x": 40, "y": 20, "width": 60, "height": 40,
              "rotation": 30, "flipY": true }
          ] }
        ] }
      ]
    }
    """

    @Test("A turned, flipped, grouped node's placement maps its box corners to the turned quad inside its bounds")
    func turnedFlippedGroupedQuad() throws {
        let document = try PenParser.parse(Data(Self.json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let node = try #require(PenLayoutEngine.node(id: "T", in: document.children))
        let rect = try #require(rects["T"])

        let placement = PenLayoutEngine.placement(of: node, rect: rect, layoutRects: rects)
        #expect(placement.box == PenRect(x: 0, y: 0, width: 60, height: 40))

        // Pen's matrix for T in its group's coordinates: its anchor, then the turn, then the flip.
        let local = Self.penMatrix(x: 40, y: 20, degrees: 30, flipY: true)
        let expected = Self.corners(of: placement.box).map(local.apply(to:))
        #expect(Self.close(placement.corners, expected), "\(placement.corners) vs \(expected)")
        // The quad's bounds are the layout rect — extent (i).
        #expect(Self.close(placement.bounds, rect.bounds), "\(placement.bounds) vs \(rect)")

        // Into the canvas: the board's move, then the group's turn about its anchor.
        let canvas = try #require(PenLayoutEngine.canvasPlacement(of: "T", in: document, layoutRects: rects))
        let chain = PenLayoutEngine.PlaneTransform.translation(x: 100, y: 50)
            .concatenating(Self.penMatrix(x: 200, y: 150, degrees: -40, flipY: false))
            .concatenating(local)
        let canvasExpected = Self.corners(of: placement.box).map(chain.apply(to:))
        #expect(Self.close(canvas.corners, canvasExpected), "\(canvas.corners) vs \(canvasExpected)")
        #expect(canvas.box == placement.box)
    }

    @Test("A group's box is its children's union from its anchor, and its placement turns it about that anchor")
    func groupPlacement() throws {
        let document = try PenParser.parse(Data(Self.json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let group = try #require(PenLayoutEngine.node(id: "G", in: document.children))
        let rect = try #require(rects["G"])

        let placement = PenLayoutEngine.placement(of: group, rect: rect, layoutRects: rects)
        #expect(placement.box == PenLayoutEngine.groupBox(of: group, in: rects))
        #expect(placement.box.x == -20)
        let anchor = placement.transform.apply(to: .zero)
        #expect(abs(anchor.x - 200) < 1e-9 && abs(anchor.y - 150) < 1e-9, "\(anchor)")
        #expect(Self.close(placement.bounds, rect.bounds))
    }

    @Test("placed(in:) composes an outer map; the canvas placement of a root is its own")
    func placedInComposes() throws {
        let document = try PenParser.parse(Data(Self.json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let board = try #require(PenLayoutEngine.node(id: "B", in: document.children))
        let own = try PenLayoutEngine.placement(of: board, rect: #require(rects["B"]), layoutRects: rects)
        #expect(PenLayoutEngine.canvasPlacement(of: "B", in: document, layoutRects: rects) == own)

        let outer = PenLayoutEngine.PlaneTransform.translation(x: 7, y: -3)
        let placed = own.placed(in: outer)
        #expect(placed.box == own.box)
        #expect(placed.transform == outer.concatenating(own.transform))
        #expect(PenLayoutEngine.canvasPlacement(of: "nope", in: document, layoutRects: rects) == nil)
    }

    // MARK: - Helpers

    /// Pen's local matrix: translate to the anchor, turn counter-clockwise in the y-down
    /// plane, flip — the flip applied to a point first.
    private static func penMatrix(x: Double, y: Double, degrees: Double, flipY: Bool) -> PenLayoutEngine.PlaneTransform {
        let radians = degrees * .pi / 180
        let turn = PenLayoutEngine.PlaneTransform(a: cos(radians), b: -sin(radians), c: sin(radians), d: cos(radians))
        let flip = PenLayoutEngine.PlaneTransform(d: flipY ? -1 : 1)
        return PenLayoutEngine.PlaneTransform.translation(x: x, y: y).concatenating(turn).concatenating(flip)
    }

    /// A rect's corners, clockwise from its top-left — the order ``PenPlacement/corners`` uses.
    private static func corners(of rect: PenRect) -> [PenPoint] {
        [
            PenPoint(x: rect.x, y: rect.y), PenPoint(x: rect.x + rect.width, y: rect.y),
            PenPoint(x: rect.x + rect.width, y: rect.y + rect.height), PenPoint(x: rect.x, y: rect.y + rect.height),
        ]
    }

    private static func close(_ lhs: [PenPoint], _ rhs: [PenPoint]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0.x - $1.x) < 1e-9 && abs($0.y - $1.y) < 1e-9 }
    }

    private static func close(_ lhs: PenRect, _ rhs: PenRect) -> Bool {
        abs(lhs.x - rhs.x) < 1e-9 && abs(lhs.y - rhs.y) < 1e-9
            && abs(lhs.width - rhs.width) < 1e-9 && abs(lhs.height - rhs.height) < 1e-9
    }
}
