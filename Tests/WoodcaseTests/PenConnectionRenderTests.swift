//
//  PenConnectionRenderTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// The renderer draws a `connection` as a straight segment from its source's anchor to
/// its target's, painted with the connection's own stroke — the way a `line` is drawn.
///
/// There is no Pen reference to hold this against: Pen 1.2.14's validator accepts a
/// connection, but neither its app nor its headless engine loads one — both drop it on
/// open and draw nothing (see `project/2026-09-26-pen-1.2.14-compatibility.md`). So the
/// probes say what Woodcase promises, not what Pen shows.
struct PenConnectionRenderTests {
    // MARK: - Helpers

    /// Two boxes, A at (0,0) 40×20 and B at (100,60) 40×20, and one connection from
    /// A's right edge (40,10) to B's left edge (100,70), with `extra` merged in.
    private func document(connection extra: String = ##","stroke":"#FF0000","strokeWidth":6"##) -> String {
        #"""
        {"version":"2.19","children":[
          {"id":"A","type":"rectangle","x":0,"y":0,"width":40,"height":20,"fill":"#0000FF"},
          {"id":"B","type":"rectangle","x":100,"y":60,"width":40,"height":20,"fill":"#0000FF"},
          {"id":"C","type":"connection","source":{"path":"A","anchor":"right"},
           "target":{"path":"B","anchor":"left"}\#(extra)}]}
        """#
    }

    private func render(_ json: String) throws -> Pixels {
        let document = try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(json)))
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 160, height: 100)))
        return try Pixels(image)
    }

    // MARK: - What is drawn

    @Test("The segment's midpoint is painted with the connection's stroke")
    func midpointIsStroked() throws {
        let pixels = try render(document())
        let mid = pixels.rgba(x: 70, y: 40)
        #expect(mid.red > 200 && mid.green < 40 && mid.blue < 40 && mid.alpha > 200, "\(mid)")
    }

    @Test("Away from the segment nothing is painted")
    func offTheSegmentIsClear() throws {
        let pixels = try render(document())
        #expect(pixels.rgba(x: 70, y: 10).alpha == 0)
        #expect(pixels.rgba(x: 70, y: 80).alpha == 0)
    }

    @Test("A connection with no stroke draws nothing, like a line")
    func noStrokeNoSegment() throws {
        let pixels = try render(document(connection: ""))
        #expect(pixels.rgba(x: 70, y: 40).alpha == 0)
    }

    @Test("A disabled connection draws nothing")
    func disabledDrawsNothing() throws {
        let pixels = try render(document(connection: ##","stroke":"#FF0000","strokeWidth":6,"enabled":false"##))
        #expect(pixels.rgba(x: 70, y: 40).alpha == 0)
    }

    @Test("A connection whose endpoint names no node draws nothing, and does not fail")
    func dangling() throws {
        let json = document().replacingOccurrences(of: #""path":"B""#, with: #""path":"Nope""#)
        let pixels = try render(json)
        #expect(pixels.rgba(x: 70, y: 40).alpha == 0)
        #expect(pixels.rgba(x: 10, y: 10).blue > 200, "the boxes still draw")
    }

    @Test("The connection's opacity applies to its stroke")
    func opacity() throws {
        let pixels = try render(document(connection: ##","stroke":"#FF0000","strokeWidth":6,"opacity":0.5"##))
        let alpha = Int(pixels.rgba(x: 70, y: 40).alpha)
        #expect((100 ... 155).contains(alpha), "alpha \(alpha)")
    }

    @Test("An endpoint inside a frame is found at its place on the canvas")
    func nestedEndpoint() throws {
        let json = #"""
        {"version":"2.19","children":[
          {"id":"F","type":"frame","layout":"none","x":80,"y":50,"width":60,"height":40,"children":[
            {"id":"K","type":"rectangle","x":20,"y":10,"width":40,"height":20}]},
          {"id":"A","type":"rectangle","x":0,"y":0,"width":40,"height":20},
          {"id":"C","type":"connection","source":{"path":"A","anchor":"right"},
           "target":{"path":"K","anchor":"left"},"stroke":"#FF0000","strokeWidth":6}]}
        """#
        // A.right = (40,10); K sits at (100,60) on the canvas, so K.left = (100,70).
        let pixels = try render(json)
        #expect(pixels.rgba(x: 70, y: 40).red > 200)
    }

    // MARK: - Pixels

    /// An RGBA8 copy of a rendered image, read at point coordinates.
    struct Pixels {
        /// One pixel's channels.
        struct RGBA: CustomStringConvertible {
            let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
            var description: String {
                "rgba(\(red),\(green),\(blue),\(alpha))"
            }
        }

        let width: Int
        let bytes: [UInt8]

        init(_ image: CGImage) throws {
            width = image.width
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try #require(CGContext(
                data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            bytes = buffer
        }

        func rgba(x: Int, y: Int) -> RGBA {
            let offset = (y * width + x) * 4
            return RGBA(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
        }
    }
}
