//
//  ConnectionSubtreeRenderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A render of one subtree — `render`'s pages, `shot`'s node — draws every top-level
/// connection whose two anchors fall inside the picture, over the subtree. A connection
/// is a top-level node of its own, so before this a render of the frame holding two
/// connected cards drew neither connector (c41x gap 5).
struct ConnectionSubtreeRenderTests {
    /// `Board` at (100,100) 200×100 holds `A` at (20,20) and `B` at (140,20), each 40×20,
    /// and `Inner` at (0,60) holding `K` at (20,10) 40×20. `C` joins A's right (160,130) to
    /// B's left (240,130) on the canvas; `Out` joins A to `Far`, a node off the board.
    private static let json = #"""
    {"version":"2.20","children":[
      {"id":"Board","type":"frame","layout":"none","x":100,"y":100,"width":200,"height":100,"children":[
        {"id":"A","type":"rectangle","x":20,"y":20,"width":40,"height":20,"fill":"#0000FF"},
        {"id":"B","type":"rectangle","x":140,"y":20,"width":40,"height":20,"fill":"#0000FF"},
        {"id":"Inner","type":"frame","layout":"none","x":0,"y":60,"width":200,"height":40,"children":[
          {"id":"K","type":"rectangle","x":20,"y":10,"width":40,"height":20}]}]},
      {"id":"Far","type":"rectangle","x":600,"y":100,"width":40,"height":20},
      {"id":"C","type":"connection","source":{"path":"A","anchor":"right"},
       "target":{"path":"B","anchor":"left"},"stroke":"#FF0000","strokeWidth":4},
      {"id":"Out","type":"connection","source":{"path":"A","anchor":"bottom"},
       "target":{"path":"Far","anchor":"left"},"stroke":"#00FF00","strokeWidth":4},
      {"id":"Low","type":"connection","source":{"path":"K","anchor":"left"},
       "target":{"path":"K","anchor":"right"},"stroke":"#FF0000","strokeWidth":4}]}
    """#

    private func render(_ root: String) throws -> PenConnectionRenderTests.Pixels {
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(Self.json)))
        let rects = PenLayoutEngine.layout(document)
        let rect = try #require(rects[root])
        let image = try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: rect.width, height: rect.height), rootNodeID: root
        ))
        return try PenConnectionRenderTests.Pixels(image)
    }

    @Test("A render of a frame draws the connection between two of its cards")
    func drawsConnectionWithin() throws {
        let pixels = try render("Board")
        // C's midpoint (200,130) on the canvas is (100,30) in the board's picture.
        let mid = pixels.rgba(x: 100, y: 30)
        #expect(mid.red > 200 && mid.blue < 60, "\(mid)")
    }

    @Test("A connection that leaves the picture is not drawn")
    func skipsConnectionLeaving() throws {
        let pixels = try render("Board")
        // Out runs from A's bottom (140,140) toward Far's left (600,110), off the board: it
        // would cross (80,37) in the picture.
        #expect(pixels.rgba(x: 80, y: 37).green < 60, "\(pixels.rgba(x: 80, y: 37))")
    }

    @Test("A render of a nested frame draws a connection inside it, where it is on the canvas")
    func nestedRoot() throws {
        let pixels = try render("Inner")
        // Low runs across K, from (120,180) to (160,180) on the canvas: (40,20) in Inner's picture.
        let mid = pixels.rgba(x: 40, y: 20)
        #expect(mid.red > 200, "\(mid)")
    }
}
