import CoreGraphics
import Testing
@testable import Woodcase

struct PenSubtreeRenderTests {
    // MARK: - Helpers

    private struct PixelReader {
        let data: [UInt8]
        let width: Int
        let height: Int
        let bytesPerRow: Int

        init?(_ image: CGImage) {
            let w = image.width
            let h = image.height
            let bpr = w * 4
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(
                data: &pixels, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: bpr,
                space: colorSpace, bitmapInfo: bitmapInfo
            ) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            data = pixels
            width = w
            height = h
            bytesPerRow = bpr
        }

        func rgba(at x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let offset = y * bytesPerRow + x * 4
            let r = data[offset]
            let g = data[offset + 1]
            let b = data[offset + 2]
            let a = data[offset + 3]
            guard a > 0, a < 255 else { return (r, g, b, a) }
            let alpha = Double(a)
            return (
                UInt8(min(255, round(Double(r) * 255.0 / alpha))),
                UInt8(min(255, round(Double(g) * 255.0 / alpha))),
                UInt8(min(255, round(Double(b) * 255.0 / alpha))),
                a
            )
        }

        func matches(at x: Int, _ y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8, tolerance: UInt8 = 2) -> Bool {
            let (pr, pg, pb, pa) = rgba(at: x, y)
            return abs(Int(pr) - Int(r)) <= Int(tolerance)
                && abs(Int(pg) - Int(g)) <= Int(tolerance)
                && abs(Int(pb) - Int(b)) <= Int(tolerance)
                && abs(Int(pa) - Int(a)) <= Int(tolerance)
        }
    }

    // MARK: - rootNodeID Tests

    @Test("rootNodeID renders only target subtree, sibling excluded")
    func subtreeOnly() throws {
        let red = PenNode(
            id: "red",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FF0000"))))
        )
        let blue = PenNode(
            id: "blue",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#0000FF"))))
        )
        let frame = PenNode(
            id: "frame",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [red, blue]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [frame])
        let rects: [String: PenRect] = [
            "frame": PenRect(x: 0, y: 0, width: 200, height: 100),
            "red": PenRect(x: 0, y: 0, width: 100, height: 100),
            "blue": PenRect(x: 100, y: 0, width: 100, height: 100),
        ]
        // Render only the red node
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            rootNodeID: "red"
        ))
        let reader = try #require(PixelReader(image))
        // Should have red content
        #expect(reader.matches(at: 50, 50, r: 255, g: 0, b: 0, a: 255))
    }

    @Test("rootNodeID translates node to origin for CGImage render")
    func translatesNodeToOrigin() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#00FF00"))))
        )
        let frame = PenNode(
            id: "frame",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [node]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [frame])
        let rects: [String: PenRect] = [
            "frame": PenRect(x: 0, y: 0, width: 200, height: 200),
            "rect1": PenRect(x: 50, y: 50, width: 100, height: 100),
        ]
        // Render just rect1 — should appear at origin in 100x100 output
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            rootNodeID: "rect1"
        ))
        let reader = try #require(PixelReader(image))
        // Node at (50,50) should be translated to (0,0) — center of output should be green
        #expect(reader.matches(at: 50, 50, r: 0, g: 255, b: 0, a: 255))
        // Top-left should also be green (node fills entire output)
        #expect(reader.matches(at: 5, 5, r: 0, g: 255, b: 0, a: 255))
    }

    @Test("rootNodeID renders children of target frame")
    func rendersChildren() throws {
        let child = PenNode(
            id: "child",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FF8800"))))
        )
        let innerFrame = PenNode(
            id: "inner",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#CCCCCC")),
                layout: PenLayoutDirection.none,
                children: [child]
            ))
        )
        let outerFrame = PenNode(
            id: "outer",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [innerFrame]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [outerFrame])
        let rects: [String: PenRect] = [
            "outer": PenRect(x: 0, y: 0, width: 200, height: 200),
            "inner": PenRect(x: 10, y: 10, width: 100, height: 100),
            "child": PenRect(x: 25, y: 25, width: 50, height: 50),
        ]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            rootNodeID: "inner"
        ))
        let reader = try #require(PixelReader(image))
        // Inner frame fill at corner
        #expect(reader.matches(at: 5, 5, r: 204, g: 204, b: 204, a: 255))
        // Child at its translated position (25-10=15, 25-10=15) center = (40, 40)
        #expect(reader.matches(at: 40, 40, r: 255, g: 136, b: 0, a: 255))
    }

    @Test("rootNodeID with invalid ID renders transparent image")
    func invalidID() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FF0000"))))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 100, height: 100)]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            rootNodeID: "nonexistent"
        ))
        let reader = try #require(PixelReader(image))
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a == 0)
    }

    @Test("rootNodeID finds deeply nested node")
    func nestedNode() throws {
        let deep = PenNode(
            id: "deep",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FF00FF"))))
        )
        let mid = PenNode(
            id: "mid",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [deep]
            ))
        )
        let top = PenNode(
            id: "top",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [mid]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [top])
        let rects: [String: PenRect] = [
            "top": PenRect(x: 0, y: 0, width: 200, height: 200),
            "mid": PenRect(x: 20, y: 20, width: 160, height: 160),
            "deep": PenRect(x: 40, y: 40, width: 80, height: 80),
        ]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 80, height: 80),
            rootNodeID: "deep"
        ))
        let reader = try #require(PixelReader(image))
        #expect(reader.matches(at: 40, 40, r: 255, g: 0, b: 255, a: 255))
    }

    @Test("rootNodeID combined with overrides")
    func subtreeWithOverrides() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FF0000"))))
        )
        let frame = PenNode(
            id: "frame",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                layout: PenLayoutDirection.none,
                children: [node]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [frame])
        let rects: [String: PenRect] = [
            "frame": PenRect(x: 0, y: 0, width: 200, height: 200),
            "rect1": PenRect(x: 50, y: 50, width: 100, height: 100),
        ]
        let overrides: [String: NodeOverrides] = [
            "rect1": NodeOverrides(fills: .single(.shorthand("#0000FF"))),
        ]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            rootNodeID: "rect1", overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        // Should be blue (overridden from red), at origin
        #expect(reader.matches(at: 50, 50, r: 0, g: 0, b: 255, a: 255))
    }
}
