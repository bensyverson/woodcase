//
//  PenLayoutUnturnedSizeTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins that the layout carries a turned node's unturned size on its rect, and that
/// ``PenLayoutEngine/unturnedBox(of:rect:layoutRects:)`` reads it rather than solving for
/// it from the turned bounds.
///
/// A turned node's rect is the bounds of its turned box, which at an odd multiple of 45°
/// cannot say how `w + h` splits between the sides. The layout sized the node before it
/// turned it, so it knows; the rect keeps that size.
struct PenLayoutUnturnedSizeTests {
    /// A fit_content flex frame holding a 70×30 rectangle, turned freely inside a
    /// `layout: none` board.
    private static func freeFrame(rotation: Double) -> String {
        ##"{"version": "2.19", "children": [{"type": "frame", "id": "board", "layout": "none", "width": 400, "height": 400, "children": [{"type": "frame", "id": "f", "x": 100, "y": 100, "rotation": \##(rotation), "layout": "horizontal", "children": [{"type": "rectangle", "id": "r", "width": 70, "height": 30}]}]}]}"##
    }

    /// The same frame as a turned child in a horizontal flex flow, beside an unturned one.
    private static func flowFrame(rotation: Double) -> String {
        ##"{"version": "2.19", "children": [{"type": "frame", "id": "board", "layout": "horizontal", "children": [{"type": "rectangle", "id": "plain", "width": 20, "height": 20}, {"type": "frame", "id": "f", "rotation": \##(rotation), "layout": "horizontal", "children": [{"type": "rectangle", "id": "r", "width": 70, "height": 30}]}]}]}"##
    }

    @Test("A freely placed turned node's rect carries its unturned size", arguments: [20.0, 45.0, -135.0, 90.0])
    func freeNodeCarriesItsSize(rotation: Double) throws {
        let rects = try PenLayoutEngine.layout(PenParser.parse(Data(Self.freeFrame(rotation: rotation).utf8)))
        let size = try #require(rects["f"]?.unturnedSize, "\(rotation)°: no unturned size")
        #expect(abs(size.width - 70) < 1e-9 && abs(size.height - 30) < 1e-9, "\(rotation)°: \(size)")
    }

    @Test("A turned flex child's rect carries the size it was measured at", arguments: [20.0, 45.0, -135.0])
    func flowChildCarriesItsSize(rotation: Double) throws {
        let rects = try PenLayoutEngine.layout(PenParser.parse(Data(Self.flowFrame(rotation: rotation).utf8)))
        let size = try #require(rects["f"]?.unturnedSize, "\(rotation)°: no unturned size")
        #expect(abs(size.width - 70) < 1e-9 && abs(size.height - 30) < 1e-9, "\(rotation)°: \(size)")
    }

    @Test("An unturned node's rect carries no separate size: it is its own")
    func unturnedNodeCarriesNothing() throws {
        let rects = try PenLayoutEngine.layout(PenParser.parse(Data(Self.flowFrame(rotation: 0).utf8)))
        let rect = try #require(rects["f"])
        #expect(rect.unturnedSize == nil)
        #expect(rect.drawnSize == PenSize(width: 70, height: 30))
    }

    @Test("A turned group's rect carries its children's union's size")
    func turnedGroupCarriesItsBox() throws {
        let json = ##"{"version": "2.19", "children": [{"type": "group", "id": "g", "x": 50, "y": 50, "rotation": 45, "children": [{"type": "rectangle", "id": "a", "x": -10, "y": 0, "width": 30, "height": 20}, {"type": "rectangle", "id": "b", "x": 40, "y": 30, "width": 10, "height": 10}]}]}"##
        let rects = try PenLayoutEngine.layout(PenParser.parse(Data(json.utf8)))
        let size = try #require(rects["g"]?.unturnedSize)
        #expect(abs(size.width - 60) < 1e-9 && abs(size.height - 40) < 1e-9, "\(size)")
    }

    @Test("A turned flow root laid out on its own carries its size")
    func subtreeLayoutCarriesTheSize() throws {
        let document = try PenParser.parse(Data(Self.flowFrame(rotation: 45).utf8))
        let rects = PenLayoutEngine.layout(document)
        let subtree = PenLayoutEngine.layoutSubtree(rootID: "f", in: document, existingRects: rects)
        #expect(subtree["f"] == rects["f"])
        #expect(subtree["f"]?.unturnedSize == PenSize(width: 70, height: 30))
    }

    @Test("Incremental layout, with and without a measurement cache, carries the size")
    func incrementalLayoutCarriesTheSize() throws {
        let document = try PenParser.parse(Data(Self.freeFrame(rotation: 45).utf8))
        let full = PenLayoutEngine.layout(document)
        let clean = PenLayoutEngine.layoutIncremental(document, previousRects: full, dirtyNodeIDs: [])
        #expect(clean == full)
        let dirty = PenLayoutEngine.layoutIncremental(document, previousRects: full, dirtyNodeIDs: ["r"])
        #expect(dirty == full)
        var cache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        let cached = PenLayoutEngine.layoutIncremental(
            document, previousRects: full, dirtyNodeIDs: ["f"], measurementCache: &cache
        )
        #expect(cached == full)
        #expect(full["f"]?.unturnedSize == PenSize(width: 70, height: 30))
    }

    @Test("The unturned box is read from the rect, never re-laid out: a fit_content node at 45°")
    func unturnedBoxReadsTheCarriedSize() throws {
        let document = try PenParser.parse(Data(Self.freeFrame(rotation: 45).utf8))
        let node = try #require(PenLayoutEngine.node(id: "f", in: document.children))
        // A size the node would never lay out at: only a read can answer it.
        let rect = PenRect(x: 0, y: 0, width: 100, height: 100, unturnedSize: PenSize(width: 60, height: 40))
        let box = PenLayoutEngine.unturnedBox(of: node, rect: rect, layoutRects: ["f": rect])
        #expect(box == PenRect(x: 0, y: 0, width: 60, height: 40))
    }

    @Test("A rect without a carried size is drawn at its own size, not solved for")
    func noSolver() throws {
        let json = ##"{"version": "2.19", "children": [{"type": "rectangle", "id": "r", "rotation": 20, "width": 100, "height": 50}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let node = try #require(document.children.first)
        let rect = PenRect(x: 0, y: 0, width: 200, height: 200)
        let box = PenLayoutEngine.unturnedBox(of: node, rect: rect, layoutRects: ["r": rect])
        #expect(box == PenRect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test("Composed canvas rects are plain bounds, the root's included")
    func canvasRectsArePlainBounds() throws {
        let json = ##"{"version": "2.19", "children": [{"type": "rectangle", "id": "r", "x": 10, "y": 10, "rotation": 30, "width": 100, "height": 50}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let rects = PenLayoutEngine.layout(document)
        #expect(rects["r"]?.unturnedSize != nil)
        let canvas = try #require(PenLayoutEngine.canvasRects(in: document, layoutRects: rects)["r"])
        #expect(canvas.unturnedSize == nil)
        #expect(canvas == rects["r"]?.bounds)
    }

    @Test("A rect's unturned size survives encoding, and an unturned rect encodes as before")
    func codableRoundTrip() throws {
        let turned = PenRect(x: 1, y: 2, width: 3, height: 4, unturnedSize: PenSize(width: 2, height: 3))
        let decoded = try JSONDecoder().decode(PenRect.self, from: JSONEncoder().encode(turned))
        #expect(decoded == turned)
        let plain = try JSONDecoder().decode([String: Double].self, from: JSONEncoder().encode(PenRect(x: 1, y: 2, width: 3, height: 4)))
        #expect(plain == ["x": 1, "y": 2, "width": 3, "height": 4])
    }
}
