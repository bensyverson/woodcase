import CoreGraphics
import Testing
@testable import Woodcase

struct PenNodeOverrideTests {
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

    // MARK: - Override Tests

    @Test("Override opacity makes node semi-transparent")
    func overrideOpacity() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0066FF"))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 100, height: 100)]
        let overrides: [String: NodeOverrides] = ["rect1": NodeOverrides(opacity: 0.5)]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a > 100)
        #expect(a < 160)
    }

    @Test("Override enabled=false hides visible node")
    func overrideDisabled() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 100, height: 100)]
        let overrides: [String: NodeOverrides] = ["rect1": NodeOverrides(enabled: false)]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a == 0)
    }

    @Test("Override enabled=true shows disabled node")
    func overrideEnabled() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(enabled: .literal(false)),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 100, height: 100)]
        let overrides: [String: NodeOverrides] = ["rect1": NodeOverrides(enabled: true)]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        #expect(reader.matches(at: 50, 50, r: 255, g: 0, b: 0, a: 255))
    }

    @Test("Override position moves node")
    func overridePosition() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#00FF00"))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 50, height: 50)]
        // Move node to (50, 50)
        let overrides: [String: NodeOverrides] = ["rect1": NodeOverrides(x: 50, y: 50)]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        // Original position should be empty
        let (_, _, _, origA) = reader.rgba(at: 10, 10)
        #expect(origA == 0)
        // New position should have green
        #expect(reader.matches(at: 60, 60, r: 0, g: 255, b: 0, a: 255))
    }

    @Test("Override size changes node dimensions")
    func overrideSize() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 100, height: 100)]
        // Shrink to 50x50
        let overrides: [String: NodeOverrides] = ["rect1": NodeOverrides(width: 50, height: 50)]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        // Inside shrunken area should be red
        #expect(reader.matches(at: 25, 25, r: 255, g: 0, b: 0, a: 255))
        // Outside shrunken area should be transparent
        let (_, _, _, a) = reader.rgba(at: 75, 75)
        #expect(a == 0)
    }

    @Test("Override fills replaces node fills")
    func overrideFills() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 100, height: 100)]
        let overrides: [String: NodeOverrides] = [
            "rect1": NodeOverrides(fills: .single(.shorthand("#0000FF"))),
        ]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        // Should be blue, not red
        #expect(reader.matches(at: 50, 50, r: 0, g: 0, b: 255, a: 255))
    }

    @Test("No override for node renders normally")
    func noOverride() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = ["rect1": PenRect(x: 0, y: 0, width: 100, height: 100)]
        // Empty overrides dict
        let overrides: [String: NodeOverrides] = [:]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        #expect(reader.matches(at: 50, 50, r: 255, g: 0, b: 0, a: 255))
    }

    @Test("Override on child only; parent unaffected")
    func overrideOnChild() throws {
        let child = PenNode(
            id: "child1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#00FF00"))
            ))
        )
        let frame = PenNode(
            id: "frame1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#FF0000")),
                layout: PenLayoutDirection.none,
                children: [child]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [frame])
        let rects: [String: PenRect] = [
            "frame1": PenRect(x: 0, y: 0, width: 100, height: 100),
            "child1": PenRect(x: 25, y: 25, width: 50, height: 50),
        ]
        // Override child to blue, parent untouched
        let overrides: [String: NodeOverrides] = [
            "child1": NodeOverrides(fills: .single(.shorthand("#0000FF"))),
        ]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100),
            overrides: overrides
        ))
        let reader = try #require(PixelReader(image))
        // Parent corner should still be red
        #expect(reader.matches(at: 5, 5, r: 255, g: 0, b: 0, a: 255))
        // Child center should be blue (overridden from green)
        #expect(reader.matches(at: 50, 50, r: 0, g: 0, b: 255, a: 255))
    }
}
