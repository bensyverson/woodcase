//
//  ConnectionInstanceEndpointTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A connector end may name a component instance by its bare path — the `ref`'s own id
/// (`Chip`), or `instance/key` for an instance inside another's slot fill
/// (`Filled/Row1`) — though the expanded document keeps no node under that id: the
/// expander roots the instance at `<path>/<component root id>`. The route is drawn from
/// the instance root's box all the same (leaf 4dmT1l).
struct ConnectionInstanceEndpointTests {
    /// `Chip` (an instance of `Comp`, 40×20, holding `Label` 10×10) at (0,0); `B` at
    /// (100,60) 40×20; `Filled` (an instance of `Host`) at (200,0), filling its free slot
    /// `Body` with `Row1`, an instance of `Item` (40×20) at (10,10) — (210,10) on the
    /// canvas. The definitions sit below the 320×100 picture. One red connection `C` runs
    /// from `source` to `B`.
    private static func json(source: String, anchor: String, target: String) -> String {
        #"""
        {"version":"2.19","children":[
          {"id":"Comp","type":"frame","reusable":true,"x":0,"y":300,"width":40,"height":20,"layout":"none",
           "children":[{"id":"Label","type":"rectangle","x":0,"y":0,"width":10,"height":10}]},
          {"id":"Item","type":"frame","reusable":true,"x":100,"y":300,"width":40,"height":20,"layout":"none"},
          {"id":"Host","type":"frame","reusable":true,"x":200,"y":300,"width":100,"height":60,"layout":"none",
           "children":[{"id":"Body","type":"frame","slot":[],"x":0,"y":0,"width":100,"height":60,"layout":"none"}]},
          {"id":"Chip","type":"ref","ref":"Comp","x":0,"y":0},
          {"id":"B","type":"rectangle","x":100,"y":60,"width":40,"height":20},
          {"id":"Filled","type":"ref","ref":"Host","x":200,"y":0,"descendants":{"Body":{"children":[
            {"id":"Row1","type":"ref","ref":"Item","x":10,"y":10}]}}},
          {"id":"C","type":"connection","source":{"path":"\#(source)","anchor":"\#(anchor)"},
           "target":{"path":"B","anchor":"\#(target)"},"stroke":"#FF0000","strokeWidth":6}]}
        """#
    }

    private func render(source: String, anchor: String, target: String) throws -> PenConnectionRenderTests.Pixels {
        let json = Self.json(source: source, anchor: anchor, target: target)
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(json)))
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 320, height: 100)))
        return try PenConnectionRenderTests.Pixels(image)
    }

    @Test("An end naming a top-level instance by its ref's id draws the route from the instance's box")
    func bareInstance() throws {
        // Chip's right (40,10) to B's left (100,70): the midpoint is (70,40).
        let mid = try render(source: "Chip", anchor: "right", target: "left").rgba(x: 70, y: 40)
        #expect(mid.red > 200 && mid.blue < 60, "\(mid)")
    }

    @Test("An end naming an instance in a slot fill by its instance path draws the route from its box")
    func instanceInSlotFill() throws {
        // Row1's bottom (230,30) to B's right (140,70): the midpoint is (185,50).
        let mid = try render(source: "Filled/Row1", anchor: "bottom", target: "right").rgba(x: 185, y: 50)
        #expect(mid.red > 200 && mid.blue < 60, "\(mid)")
    }

    @Test("An end naming the instance that holds the slot fill draws the route from its box")
    func fillingInstance() throws {
        // Filled's left (200,30) to B's top (120,60): the midpoint is (160,45).
        let mid = try render(source: "Filled", anchor: "left", target: "top").rgba(x: 160, y: 45)
        #expect(mid.red > 200 && mid.blue < 60, "\(mid)")
    }

    @Test("An end naming a node inside an instance still draws from that node")
    func descendant() throws {
        // Label's right (10,5) to B's left (100,70): the midpoint is (55,37.5).
        let mid = try render(source: "Chip/Label", anchor: "right", target: "left").rgba(x: 55, y: 37)
        #expect(mid.red > 200 && mid.blue < 60, "\(mid)")
    }

    @Test("A render of one board draws a connector into an instance on it")
    func subtree() throws {
        // Board at (50,50) holds Chip at (0,0) and B at (100,60): Chip's right (90,60) to
        // B's left (150,120) on the canvas, whose midpoint (120,90) is (70,40) in the picture.
        let json = #"""
        {"version":"2.19","children":[
          {"id":"Comp","type":"frame","reusable":true,"x":0,"y":300,"width":40,"height":20,"layout":"none"},
          {"id":"Board","type":"frame","layout":"none","x":50,"y":50,"width":160,"height":100,"children":[
            {"id":"Chip","type":"ref","ref":"Comp","x":0,"y":0},
            {"id":"B","type":"rectangle","x":100,"y":60,"width":40,"height":20}]},
          {"id":"C","type":"connection","source":{"path":"Chip","anchor":"right"},
           "target":{"path":"B","anchor":"left"},"stroke":"#FF0000","strokeWidth":6}]}
        """#
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(json)))
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: 160, height: 100), rootNodeID: "Board"
        ))
        let mid = try PenConnectionRenderTests.Pixels(image).rgba(x: 70, y: 40)
        #expect(mid.red > 200 && mid.blue < 60, "\(mid)")
    }

    @Test("Endpoint rects key each instance under the path its connector ends name, beside every canvas rect")
    func endpointRects() throws {
        let json = Self.json(source: "Chip", anchor: "right", target: "left")
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(json)))
        let layoutRects = PenLayoutEngine.layout(document)
        let canvas = PenLayoutEngine.canvasRects(in: document, layoutRects: layoutRects)

        let rects = PenLayoutEngine.connectionEndpointRects(in: document, layoutRects: layoutRects)

        #expect(rects["Chip"] == canvas["Chip/Comp"])
        #expect(rects["Filled"] == canvas["Filled/Host"])
        #expect(rects["Filled/Row1"] == canvas["Filled/Row1/Item"])
        #expect(rects["Filled/Row1"] == PenRect(x: 210, y: 10, width: 40, height: 20))
        #expect(rects["Chip/Label"] == canvas["Chip/Label"])
        #expect(Set(rects.keys).subtracting(canvas.keys) == ["Chip", "Filled", "Filled/Row1"])
        for (id, rect) in canvas {
            #expect(rects[id] == rect, "\(id)")
        }
    }
}
