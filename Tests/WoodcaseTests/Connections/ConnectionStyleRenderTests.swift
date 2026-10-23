//
//  ConnectionStyleRenderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// The CG renderer draws a connection's elbow route and its arrowheads, from the same
/// geometry ``PenNode/ConnectionData/Drawing`` hands every renderer.
///
/// Pen draws no connection at all (it drops the node on open), so these probes pin what
/// Woodcase promises.
struct ConnectionStyleRenderTests {
    /// A at (0,0) 40×20 and B at (100,60) 40×20; C from A's right (40,10) to B's left
    /// (100,70), 2 pt red, with `metadata` as its metadata.
    private func render(metadata: String?) throws -> PenConnectionRenderTests.Pixels {
        let meta = metadata.map { #","metadata":{"type":"woodcase","woodcase":\#($0)}"# } ?? ""
        let json = #"""
        {"version":"2.20","children":[
          {"id":"A","type":"rectangle","x":0,"y":0,"width":40,"height":20,"fill":"#0000FF"},
          {"id":"B","type":"rectangle","x":100,"y":60,"width":40,"height":20,"fill":"#0000FF"},
          {"id":"C","type":"connection","source":{"path":"A","anchor":"right"},
           "target":{"path":"B","anchor":"left"},"stroke":"#FF0000","strokeWidth":2\#(meta)}]}
        """#
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(json)))
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 160, height: 100)))
        return try PenConnectionRenderTests.Pixels(image)
    }

    private func isRed(_ pixel: PenConnectionRenderTests.Pixels.RGBA) -> Bool {
        pixel.red > 200 && pixel.green < 60 && pixel.blue < 60 && pixel.alpha > 200
    }

    @Test("An elbow is drawn along its runs, not along the diagonal")
    func elbow() throws {
        let pixels = try render(metadata: #"{"routing":"elbow"}"#)
        #expect(isRed(pixels.rgba(x: 55, y: 10)), "first run, \(pixels.rgba(x: 55, y: 10))")
        #expect(isRed(pixels.rgba(x: 70, y: 40)), "middle run")
        #expect(isRed(pixels.rgba(x: 85, y: 70)), "last run")
        #expect(pixels.rgba(x: 55, y: 25).alpha == 0, "the straight diagonal is not drawn")
    }

    @Test("Without keys the connection is still the straight segment")
    func straightByDefault() throws {
        let pixels = try render(metadata: nil)
        #expect(isRed(pixels.rgba(x: 55, y: 25)))
        #expect(pixels.rgba(x: 55, y: 10).alpha == 0)
    }

    @Test("A triangle arrowhead is filled in the stroke's paint at the target")
    func triangle() throws {
        let headed = try render(metadata: #"{"routing":"elbow","endArrowhead":"triangle"}"#)
        // 14 long from the tip at (100,70): at x 92 it spans y 66…74.
        #expect(isRed(headed.rgba(x: 92, y: 67)), "\(headed.rgba(x: 92, y: 67))")
        let bare = try render(metadata: #"{"routing":"elbow"}"#)
        #expect(bare.rgba(x: 92, y: 67).alpha == 0)
    }

    @Test("A circle arrowhead is a disc at the source")
    func circle() throws {
        let pixels = try render(metadata: #"{"routing":"elbow","startArrowhead":"circle"}"#)
        // Radius 6, centered at (46,10).
        #expect(isRed(pixels.rgba(x: 46, y: 14)))
        #expect(pixels.rgba(x: 46, y: 18).alpha == 0)
    }

    @Test("A chevron arrowhead is stroked, open at its back")
    func chevron() throws {
        let pixels = try render(metadata: #"{"routing":"elbow","endArrowhead":"chevron"}"#)
        // The arms run from about (84,77) and (84,63) to the tip near (98,70).
        #expect(isRed(pixels.rgba(x: 91, y: 73)), "an arm, \(pixels.rgba(x: 91, y: 73))")
        #expect(pixels.rgba(x: 88, y: 67).alpha == 0, "the inside of the chevron is open")
    }
}
