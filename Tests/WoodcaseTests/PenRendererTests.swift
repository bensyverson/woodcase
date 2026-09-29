import CoreGraphics
import Testing
@testable import Woodcase

struct PenRendererTests {
    // MARK: - Pixel Reading Helper

    /// Extracts RGBA values from a CGImage at a given pixel coordinate.
    /// Uses sRGB color space, premultiplied-last alpha, big-endian byte order.
    private struct PixelReader {
        let data: [UInt8]
        let width: Int
        let height: Int
        let bytesPerRow: Int

        init?(_ image: CGImage) {
            let w = image.width
            let h = image.height
            let bpp = 4
            let bpr = w * bpp
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue

            var pixels = [UInt8](repeating: 0, count: w * h * bpp)
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

        /// Returns (R, G, B, A) at the given pixel coordinate, un-premultiplied.
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

        /// Returns true if the pixel at (x, y) matches expected RGBA within tolerance.
        func matches(at x: Int, _ y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8, tolerance: UInt8 = 2) -> Bool {
            let (pr, pg, pb, pa) = rgba(at: x, y)
            return abs(Int(pr) - Int(r)) <= Int(tolerance)
                && abs(Int(pg) - Int(g)) <= Int(tolerance)
                && abs(Int(pb) - Int(b)) <= Int(tolerance)
                && abs(Int(pa) - Int(a)) <= Int(tolerance)
        }
    }

    // MARK: - Test Helpers

    /// Creates a minimal document with a single node and renders it.
    /// Canvas is white, 100×100 at 1x scale.
    private func renderSingleNode(
        _ node: PenNode,
        rect: PenRect = PenRect(x: 0, y: 0, width: 100, height: 100),
        canvasSize: CGSize = CGSize(width: 100, height: 100)
    ) -> CGImage? {
        let doc = PenDocument(version: "2.9", children: [node])
        let layoutRects: [String: PenRect] = [node.id: rect]
        return PenRenderer.render(doc, layoutRects: layoutRects, size: canvasSize)
    }

    /// Creates a document with a frame containing children and renders it.
    private func renderFrame(
        id: String = "frame",
        frameRect: PenRect = PenRect(x: 0, y: 0, width: 100, height: 100),
        frameFill: String? = nil,
        clip: Bool = false,
        children: [PenNode] = [],
        childRects: [String: PenRect] = [:],
        canvasSize: CGSize = CGSize(width: 100, height: 100)
    ) -> CGImage? {
        let frame = PenNode(
            id: id,
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                clip: clip ? .literal(true) : nil,
                fills: frameFill.map { PenFills.single(.shorthand($0)) },
                layout: PenLayoutDirection.none,
                children: children
            ))
        )
        let doc = PenDocument(version: "2.9", children: [frame])
        var rects = childRects
        rects[id] = frameRect
        return PenRenderer.render(doc, layoutRects: rects, size: canvasSize)
    }

    // MARK: - Solid Fill Tests

    @Test("Red rectangle fills center pixel red")
    func redRectangle() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        // Center pixel should be red
        #expect(reader.matches(at: 50, 50, r: 255, g: 0, b: 0, a: 255))
    }

    @Test("Blue rectangle with hex color fill")
    func blueColorFill() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.color(PenFill.PenColorFill(color: .literal("#0066FF"))))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        #expect(reader.matches(at: 50, 50, r: 0, g: 102, b: 255, a: 255))
    }

    @Test("Rectangle with no fill renders transparent")
    func noFill() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData())
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        // Should be transparent (no fill, no background)
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a == 0)
    }

    // MARK: - Multiple Fills

    @Test("Multiple fills layer bottom to top")
    func multipleFills() throws {
        // Yellow base + semi-transparent red on top
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .multiple([
                    .shorthand("#FFFF00"),
                    .shorthand("#FF000080"),
                ])
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        let (r, g, _, a) = reader.rgba(at: 50, 50)
        // Result should be a blend: red channel high, green reduced, alpha = 255
        #expect(r > 200)
        #expect(g > 50) // yellow shows through
        #expect(a == 255)
    }

    // MARK: - Disabled Node

    @Test("Disabled node is not rendered")
    func disabledNode() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(enabled: .literal(false)),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        // Should be transparent — node is disabled
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a == 0)
    }

    // MARK: - Ellipse

    @Test("Filled ellipse has color at center")
    func filledEllipse() throws {
        let node = PenNode(
            id: "ellipse1",
            common: PenNodeCommon(),
            kind: .ellipse(PenNode.EllipseData(
                fills: .single(.shorthand("#FF8800"))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        #expect(reader.matches(at: 50, 50, r: 255, g: 136, b: 0, a: 255))
    }

    // MARK: - Stroke

    @Test("Rectangle with center stroke has stroke color at edge")
    func strokeCenter() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#DDDDDD")),
                stroke: .single(.shorthand("#FF0000")),
                strokeWidth: .uniform(.literal(6)),
                strokeAlignment: .center
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        // Center should be gray fill
        #expect(reader.matches(at: 50, 50, r: 221, g: 221, b: 221, a: 255))
        // Edge (x=1) should have red stroke
        let (r, _, _, _) = reader.rgba(at: 1, 50)
        #expect(r > 200) // Stroke is red
    }

    // MARK: - Frame with Child

    @Test("Frame renders child at correct position")
    func frameWithChild() throws {
        let child = PenNode(
            id: "child1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#4CAF50"))
            ))
        )
        let image = try #require(renderFrame(
            frameFill: "#E8E8E8",
            children: [child],
            childRects: ["child1": PenRect(x: 25, y: 25, width: 50, height: 50)]
        ))
        let reader = try #require(PixelReader(image))
        // Child center (25+25=50, 25+25=50) should be green
        #expect(reader.matches(at: 50, 50, r: 76, g: 175, b: 80, a: 255))
        // Outside child (10, 10) should be gray frame fill
        #expect(reader.matches(at: 10, 10, r: 232, g: 232, b: 232, a: 255))
    }

    @Test("Frame with clip hides overflowing child")
    func frameClip() throws {
        // Child is larger than frame and offset to overflow
        let child = PenNode(
            id: "child1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let image = try #require(renderFrame(
            frameFill: "#FFFFFF",
            clip: true,
            children: [child],
            childRects: ["child1": PenRect(x: 50, y: 50, width: 200, height: 200)],
            canvasSize: CGSize(width: 200, height: 200)
        ))
        let reader = try #require(PixelReader(image))
        // Inside frame + child overlap (75, 75) should be red
        #expect(reader.matches(at: 75, 75, r: 255, g: 0, b: 0, a: 255))
        // Outside frame bounds (150, 150) should be transparent — child clipped
        let (_, _, _, a) = reader.rgba(at: 150, 150)
        #expect(a == 0)
    }

    // MARK: - Polygon

    @Test("Hexagon fills center pixel")
    func hexagonFill() throws {
        let node = PenNode(
            id: "hex1",
            common: PenNodeCommon(),
            kind: .polygon(PenNode.PolygonData(
                polygonCount: .literal(6),
                fills: .single(.shorthand("#7B1FA2"))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        #expect(reader.matches(at: 50, 50, r: 123, g: 31, b: 162, a: 255))
    }

    // MARK: - Line

    @Test("Diagonal line renders with stroke color")
    func diagonalLine() throws {
        let node = PenNode(
            id: "line1",
            common: PenNodeCommon(),
            kind: .line(PenNode.LineData(
                stroke: .single(.shorthand("#333333")),
                strokeWidth: .uniform(.literal(6)),
                strokeAlignment: .center
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        // Center of diagonal (50, 50) should have dark gray stroke
        let (r, g, b, a) = reader.rgba(at: 50, 50)
        #expect(a > 200) // Should be mostly opaque at center of a 6px line
        #expect(r < 100) // Should be dark
        #expect(g < 100)
        #expect(b < 100)
    }

    // MARK: - Path

    @Test("Path with SVG geometry renders fill")
    func pathWithFill() throws {
        // Simple square path covering the whole rect
        let node = PenNode(
            id: "path1",
            common: PenNodeCommon(),
            kind: .path(PenNode.PathData(
                geometry: "M 0 0 L 100 0 L 100 100 L 0 100 Z",
                fills: .single(.shorthand("#FF6B00"))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        #expect(reader.matches(at: 50, 50, r: 255, g: 107, b: 0, a: 255))
    }

    // MARK: - Disabled Fill

    @Test("Disabled fill is skipped")
    func disabledFill() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.color(PenFill.PenColorFill(
                    enabled: .literal(false),
                    color: .literal("#FF0000")
                )))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a == 0)
    }

    // MARK: - Corner Radius

    @Test("Rounded rectangle has transparent corner")
    func roundedCorner() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                cornerRadius: .uniform(.literal(20)),
                fills: .single(.shorthand("#0066FF"))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        // Center should be blue
        #expect(reader.matches(at: 50, 50, r: 0, g: 102, b: 255, a: 255))
        // Top-left corner (1, 1) should be transparent due to rounding
        let (_, _, _, a) = reader.rgba(at: 1, 1)
        #expect(a < 128) // Corner is clipped
    }

    // MARK: - Opacity

    @Test("Node with 50% opacity renders semi-transparent")
    func nodeOpacity() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(opacity: .literal(0.5)),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0066FF"))
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        // Alpha should be roughly 128 (50% of 255)
        #expect(a > 100)
        #expect(a < 160)
    }

    // MARK: - Rotation

    @Test("Rotated rectangle has transparent corner where original had fill")
    func rotatedRectangle() throws {
        // A 60×60 rect rotated 45°, centered in a 100×100 canvas. Its layout rect is its
        // turned bounds (60√2 square), as the layout writes it: the renderer draws the
        // unturned box centered in those bounds. The rect used to be the unturned 60×60 box
        // itself, with no declared size, which the renderer read as a node of the bounds'
        // size; since leaf nAuBKh it recovers the unturned size from the bounds, which needs
        // the rect to be the bounds and, at 45°, a declared side.
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(rotation: .literal(45)),
            kind: .rectangle(PenNode.RectangleData(
                width: .fixed(60), height: .fixed(60),
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let bounds = 60 * 2.0.squareRoot()
        let image = try #require(renderSingleNode(
            node,
            rect: PenRect(x: 50 - bounds / 2, y: 50 - bounds / 2, width: bounds, height: bounds)
        ))
        let reader = try #require(PixelReader(image))
        // Center should still be red
        let (cr, _, _, ca) = reader.rgba(at: 50, 50)
        #expect(cr > 200)
        #expect(ca > 200)
        // Top-left corner of canvas should be transparent (rotated rect doesn't reach there)
        let (_, _, _, cornerA) = reader.rgba(at: 5, 5)
        #expect(cornerA < 50)
    }

    // MARK: - FlipX

    @Test("FlipX mirrors content horizontally")
    func flipX() throws {
        // Frame with a child on the left side. After flipX, child should appear on right.
        let child = PenNode(
            id: "child1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let frame = PenNode(
            id: "frame1",
            common: PenNodeCommon(flipX: .literal(true)),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#FFFFFF")),
                layout: PenLayoutDirection.none,
                children: [child]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [frame])
        let rects: [String: PenRect] = [
            "frame1": PenRect(x: 0, y: 0, width: 100, height: 100),
            "child1": PenRect(x: 0, y: 0, width: 30, height: 100),
        ]
        let image = try #require(PenRenderer.render(
            doc, layoutRects: rects, size: CGSize(width: 100, height: 100)
        ))
        let reader = try #require(PixelReader(image))
        // With flipX, child at x=0..30 should appear at x=70..100
        let (rr, _, _, _) = reader.rgba(at: 85, 50) // Right side — should be red
        #expect(rr > 200)
        let (lr, _, _, _) = reader.rgba(at: 15, 50) // Left side — should be white
        #expect(lr > 200) // White has R=255
    }
}
