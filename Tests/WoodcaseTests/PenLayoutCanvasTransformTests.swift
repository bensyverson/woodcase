//
//  PenLayoutCanvasTransformTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins ``PenLayoutEngine/canvasTransform(of:in:layoutRects:)``: the affine map from a
/// node's own coordinates to the canvas, composed as ``PenRenderer`` draws it.
///
/// Two oracles. The renderer's pixels: markers in a turned group inside a turned and
/// flipped frame are drawn where the map sends their boxes — their bounds and, since
/// bounds cannot see a flip, their centers. And ``PenLayoutEngine/canvasRects(in:layoutRects:)``:
/// the map carries every node's unturned box to its canvas rect.
struct PenLayoutCanvasTransformTests {
    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// A turned, flipped frame holding a turned group of two markers — one of them
    /// reaching left of and above the group's anchor — a marker of its own, and a flex
    /// frame turned in its flow.
    private static let json = """
    {
      "version": "2.19",
      "children": [
        { "type": "frame", "id": "F", "x": 380, "y": 260, "width": 240, "height": 160, "rotation": 30,
          "flipX": true, "layout": "none", "children": [
          { "type": "rectangle", "id": "M3", "x": 10, "y": 10, "width": 20, "height": 10, "fill": "#00FF00" },
          { "type": "group", "id": "G", "x": 120, "y": 60, "rotation": -40, "children": [
            { "type": "rectangle", "id": "M1", "x": -20, "y": -10, "width": 30, "height": 16, "fill": "#FF0000" },
            { "type": "rectangle", "id": "M2", "x": 30, "y": 20, "width": 12, "height": 24, "fill": "#0000FF" }
          ] }
        ] },
        { "type": "frame", "id": "R", "x": 450, "y": 450, "layout": "horizontal", "gap": 10, "children": [
          { "type": "rectangle", "id": "R1", "width": 20, "height": 20 },
          { "type": "frame", "id": "R2", "rotation": 45, "flipY": true, "layout": "vertical", "children": [
            { "type": "rectangle", "id": "M4", "width": 50, "height": 14, "fill": "#FF00FF" },
            { "type": "rectangle", "id": "M5", "width": 20, "height": 30, "fill": "#00FFFF" }
          ] }
        ] }
      ]
    }
    """

    /// Each marker's fill, for finding its pixels in the render.
    private static let markerColors: [String: (r: UInt8, g: UInt8, b: UInt8)] = [
        "M1": (255, 0, 0), "M2": (0, 0, 255), "M3": (0, 255, 0), "M4": (255, 0, 255), "M5": (0, 255, 255),
    ]

    private static let canvasSize = CGSize(width: 800, height: 700)

    @Test("Each marker is drawn where its canvas transform sends its box")
    func matchesTheRenderersPixels() throws {
        let document = try PenParser.parse(Data(Self.json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: Self.canvasSize))
        let pixels = try Self.pixels(in: image, colors: Self.markerColors)

        for id in Self.markerColors.keys.sorted() {
            let drawn = try #require(pixels[id], "no pixels of \(id)")
            let node = try #require(PenLayoutEngine.node(id: id, in: document.children))
            let rect = try #require(rects[id])
            let box = PenLayoutEngine.unturnedBox(of: node, rect: rect, layoutRects: rects)
            let transform = try #require(PenLayoutEngine.canvasTransform(of: id, in: document, layoutRects: rects))
            let bounds = transform.bounds(of: box)
            // Only fully opaque pixels count, and a corner turned 45° is a sharp tip, so the
            // pixels' bounds sit up to 1.6 pt inside the box's; the center is exact.
            #expect(Self.isClose(bounds, drawn.bounds, tolerance: 2), "\(id): \(bounds) vs pixels \(drawn.bounds)")
            let center = transform.apply(to: PenPoint(x: box.x + box.width / 2, y: box.y + box.height / 2))
            #expect(
                abs(center.x - drawn.centroid.x) < 1 && abs(center.y - drawn.centroid.y) < 1,
                "\(id): center \(center) vs pixels' \(drawn.centroid)"
            )
        }
    }

    @Test("Every node's unturned box, mapped, is its canvas rect", arguments: ["inline", "render-transformed-free", "render-free-groups", "render-rotated-free"])
    func matchesCanvasRects(source: String) throws {
        let document = try Self.document(source)
        let rects = PenLayoutEngine.layout(document)
        let canvas = PenLayoutEngine.canvasRects(in: document, layoutRects: rects)
        #expect(canvas.count > 5)
        for (id, want) in canvas.sorted(by: { $0.key < $1.key }) {
            let node = try #require(PenLayoutEngine.node(id: id, in: document.children))
            let rect = try #require(rects[id])
            let box = PenLayoutEngine.unturnedBox(of: node, rect: rect, layoutRects: rects)
            let transform = try #require(PenLayoutEngine.canvasTransform(of: id, in: document, layoutRects: rects))
            let got = transform.bounds(of: box)
            #expect(Self.isClose(got, want, tolerance: 1e-9), "\(source) \(id): \(got) vs \(want)")
        }
    }

    @Test("A freely placed node's own origin lands on its anchor, turned and flipped about it")
    func freeNodeTurnsAboutItsAnchor() throws {
        let json = ##"{"version": "2.19", "children": [{"type": "rectangle", "id": "r", "x": 100, "y": 80, "width": 60, "height": 20, "rotation": 30, "flipY": true}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let transform = try #require(PenLayoutEngine.canvasTransform(of: "r", in: document, layoutRects: rects))
        let origin = transform.apply(to: .zero)
        #expect(abs(origin.x - 100) < 1e-9 && abs(origin.y - 80) < 1e-9, "\(origin)")
        // Pen's 30° is counter-clockwise: the top edge rises to the right in the y-down canvas.
        let corner = transform.apply(to: PenPoint(x: 60, y: 0))
        let radians = 30 * Double.pi / 180
        #expect(abs(corner.x - (100 + 60 * cos(radians))) < 1e-9, "\(corner)")
        #expect(abs(corner.y - (80 - 60 * sin(radians))) < 1e-9, "\(corner)")
        // The flip mirrors the box's height below its top edge to above it.
        let below = transform.apply(to: PenPoint(x: 0, y: 20))
        #expect(abs(below.x - (100 - 20 * sin(radians))) < 1e-9 && abs(below.y - (80 - 20 * cos(radians))) < 1e-9, "\(below)")
    }

    @Test("An unturned root's transform is a move to its rect; an unknown node has none")
    func plainRootAndUnknownNode() throws {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "f", "x": 40, "y": 30, "width": 60, "height": 20, "layout": "none", "children": [{"type": "rectangle", "id": "c", "x": 5, "y": 6, "width": 10, "height": 10}]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let rects = PenLayoutEngine.layout(document)
        #expect(PenLayoutEngine.canvasTransform(of: "f", in: document, layoutRects: rects) == .translation(x: 40, y: 30))
        #expect(PenLayoutEngine.canvasTransform(of: "c", in: document, layoutRects: rects) == .translation(x: 45, y: 36))
        #expect(PenLayoutEngine.canvasTransform(of: "nope", in: document, layoutRects: rects) == nil)
        let frameOnly = try ["f": #require(rects["f"])]
        #expect(PenLayoutEngine.canvasTransform(of: "c", in: document, layoutRects: frameOnly) == nil)
    }

    @Test("The inverse carries a canvas point back into a node's own coordinates")
    func inverseRoundTrips() throws {
        let document = try PenParser.parse(Data(Self.json.utf8))
        let rects = PenLayoutEngine.layout(document)
        let transform = try #require(PenLayoutEngine.canvasTransform(of: "G", in: document, layoutRects: rects))
        let inverse = try #require(transform.inverted())
        let point = PenPoint(x: 13, y: -7)
        let back = inverse.apply(to: transform.apply(to: point))
        #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9, "\(back)")
        #expect(PenLayoutEngine.PlaneTransform(a: 0, b: 0, c: 0, d: 0, tx: 1, ty: 1).inverted() == nil)
        #if canImport(CoreGraphics)
            let mapped = CGPoint(x: 13, y: -7).applying(transform.cgAffineTransform)
            let expected = transform.apply(to: point)
            #expect(abs(mapped.x - expected.x) < 1e-9 && abs(mapped.y - expected.y) < 1e-9)
        #endif
    }

    // MARK: - Helpers

    /// The inline document, or a fixture parsed and resolved as the renderer reads it.
    private static func document(_ source: String) throws -> PenDocument {
        guard source != "inline" else { return try PenParser.parse(Data(json.utf8)) }
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent("\(source).pen"))
        return try PenVariableResolver.resolve(PenRefExpander.expand(PenParser.parse(data)))
    }

    private static func isClose(_ lhs: PenRect, _ rhs: PenRect, tolerance: Double) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
            && abs(lhs.x + lhs.width - rhs.x - rhs.width) <= tolerance
            && abs(lhs.y + lhs.height - rhs.y - rhs.height) <= tolerance
    }

    /// The bounds and centroid of each color's opaque-enough pixels, in points (the
    /// render is at 1×).
    private static func pixels(
        in image: CGImage,
        colors: [String: (r: UInt8, g: UInt8, b: UInt8)]
    ) throws -> [String: (bounds: PenRect, centroid: PenPoint)] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)

        var found: [String: (minX: Int, minY: Int, maxX: Int, maxY: Int, sumX: Double, sumY: Double, count: Double)] = [:]
        for row in 0 ..< height {
            for column in 0 ..< width {
                let offset = (row * width + column) * 4
                guard bytes[offset + 3] >= 250 else { continue }
                for (id, color) in colors where near(bytes[offset], color.r) && near(bytes[offset + 1], color.g)
                    && near(bytes[offset + 2], color.b)
                {
                    var entry = found[id] ?? (column, row, column, row, 0, 0, 0)
                    entry = (
                        min(entry.minX, column), min(entry.minY, row), max(entry.maxX, column), max(entry.maxY, row),
                        entry.sumX + Double(column) + 0.5, entry.sumY + Double(row) + 0.5, entry.count + 1
                    )
                    found[id] = entry
                }
            }
        }
        return found.mapValues { entry in
            (
                PenRect(
                    x: Double(entry.minX), y: Double(entry.minY),
                    width: Double(entry.maxX - entry.minX + 1), height: Double(entry.maxY - entry.minY + 1)
                ),
                PenPoint(x: entry.sumX / entry.count, y: entry.sumY / entry.count)
            )
        }
    }

    private static func near(_ value: UInt8, _ target: UInt8) -> Bool {
        abs(Int(value) - Int(target)) < 64
    }
}
