import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// `PenRenderer.render(_:layoutRects:rootNodeIDs:bounds:scale:)`: a selection that spans
/// parents, each root drawn where the canvas draws it — through its ancestors' placements
/// and clips — and nothing else.
struct PenRendererMultiRootTests {
    /// `p1` at (100, 50) holds `a`; `p2`, a clipping frame turned 30° at (250, 20), holds `b`,
    /// which overhangs it; `c` sits apart at the origin. No parent paints anything.
    private static let canvas = """
    [
      {"type": "rectangle", "id": "c", "x": 0, "y": 0, "width": 50, "height": 50, "fill": "#00FF00"},
      {"type": "frame", "id": "p1", "x": 100, "y": 50, "width": 100, "height": 100, "layout": "none",
       "children": [
         {"type": "rectangle", "id": "a", "x": 10, "y": 20, "width": 30, "height": 40, "fill": "#FF0000",
          "cornerRadius": 6}
       ]},
      {"type": "frame", "id": "p2", "x": 250, "y": 20, "width": 80, "height": 80, "layout": "none",
       "clip": true, "rotation": 30,
       "children": [
         {"type": "ellipse", "id": "b", "x": 30, "y": 30, "width": 90, "height": 70, "fill": "#0000FF"}
       ]}
    ]
    """

    private static func layout(_ children: String) throws -> (PenDocument, [String: PenRect]) {
        let document = try PenParser.parse(Data(#"{"version": "2.17", "children": \#(children)}"#.utf8))
        return (document, PenLayoutEngine.layout(document))
    }

    @Test("Two roots under different parents match the same region cropped from the full render")
    func matchesCroppedFullRender() throws {
        let (document, rects) = try Self.layout(Self.canvas)
        let bounds = PenRect(x: 100, y: 0, width: 300, height: 200)
        let scale: CGFloat = 2

        let selection = try #require(PenRenderer.render(
            document, layoutRects: rects, rootNodeIDs: ["a", "b"], bounds: bounds, scale: scale
        ))
        let full = try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: 400, height: 200), scale: scale
        ))
        let cropped = try #require(full.cropping(to: CGRect(x: 200, y: 0, width: 600, height: 400)))

        #expect(selection.width == 600)
        #expect(selection.height == 400)
        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: selection, and: cropped)
        #expect(mae < 0.01, "MAE \(mae)")
        // The overhang is really cut: the full render shows clipping happened at all.
        let unclipped = try #require(PenRenderer.render(
            document, layoutRects: rects, rootNodeIDs: ["b"], bounds: bounds, scale: scale
        ))
        #expect(PenSnapshotTestHelpers.meanAbsoluteError(between: unclipped, and: cropped) > 0.1)
    }

    @Test("A root's ancestors paint nothing of their own")
    func parentsAreNotDrawn() throws {
        let (document, rects) = try Self.layout("""
        [{"type": "frame", "id": "p", "x": 0, "y": 0, "width": 100, "height": 100, "layout": "none",
          "fill": "#00FF00",
          "children": [{"type": "rectangle", "id": "a", "x": 50, "y": 50, "width": 20, "height": 20, "fill": "#FF0000"}]}]
        """)
        let image = try #require(PenRenderer.render(
            document, layoutRects: rects, rootNodeIDs: ["a"], bounds: PenRect(x: 0, y: 0, width: 100, height: 100)
        ))
        let pixels = try #require(AlphaGrid(image))
        #expect(pixels.alpha(x: 10, y: 10) == 0, "the parent's green is left out")
        #expect(pixels.alpha(x: 60, y: 60) == 255, "the root lands at its canvas position")
    }

    @Test("A root inside another root is drawn once")
    func descendantRootIsDrawnOnce() throws {
        let (document, rects) = try Self.layout("""
        [{"type": "frame", "id": "p", "x": 0, "y": 0, "width": 40, "height": 40, "layout": "none",
          "children": [{"type": "rectangle", "id": "a", "x": 0, "y": 0, "width": 40, "height": 40, "fill": "#FF000080"}]}]
        """)
        let bounds = PenRect(x: 0, y: 0, width: 40, height: 40)
        let both = try #require(PenRenderer.render(document, layoutRects: rects, rootNodeIDs: ["p", "a"], bounds: bounds))
        let one = try #require(PenRenderer.render(document, layoutRects: rects, rootNodeIDs: ["p"], bounds: bounds))
        #expect(PenSnapshotTestHelpers.meanAbsoluteError(between: both, and: one) == 0)
    }

    @Test("No root the document has draws an empty, transparent image")
    func unknownRoots() throws {
        let (document, rects) = try Self.layout(Self.canvas)
        let image = try #require(PenRenderer.render(
            document, layoutRects: rects, rootNodeIDs: ["nope"], bounds: PenRect(x: 0, y: 0, width: 10, height: 10)
        ))
        #expect(try #require(AlphaGrid(image)).alpha(x: 5, y: 5) == 0)
    }

    @Test("The roots' canvas painted extent is the union of each one's")
    func unionOfPaintedExtents() throws {
        let (document, rects) = try Self.layout(Self.canvas)
        let a = try #require(PenLayoutEngine.canvasPaintedExtent(of: "a", in: document, layoutRects: rects))
        let c = try #require(PenLayoutEngine.canvasPaintedExtent(of: "c", in: document, layoutRects: rects))
        let union = try #require(PenLayoutEngine.canvasPaintedExtent(of: ["a", "c", "nope"], in: document, layoutRects: rects))
        #expect(union.x == min(a.x, c.x))
        #expect(union.y == min(a.y, c.y))
        #expect(union.x + union.width == max(a.x + a.width, c.x + c.width))
        #expect(union.y + union.height == max(a.y + a.height, c.y + c.height))
        #expect(PenLayoutEngine.canvasPaintedExtent(of: ["nope"], in: document, layoutRects: rects) == nil)
    }
}

/// An image's pixels, readable by coordinate, top-left origin.
private struct AlphaGrid {
    let bytes: [UInt8]
    let width: Int

    init?(_ image: CGImage) {
        width = image.width
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bytes = pixels
    }

    func alpha(x: Int, y: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + 3]
    }
}
