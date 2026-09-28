import CoreGraphics
import Testing
@testable import Woodcase

struct PenTextRendererTests {
    // MARK: - Pixel Reading Helper

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

        /// Returns true if the pixel has any visible ink (alpha > 0).
        func hasInk(at x: Int, _ y: Int) -> Bool {
            let (_, _, _, a) = rgba(at: x, y)
            return a > 0
        }

        /// Scans a horizontal line for any non-transparent pixels.
        func hasInkInRow(_ y: Int, fromX: Int = 0, toX: Int? = nil) -> Bool {
            let maxX = toX ?? width
            for x in fromX ..< maxX {
                if hasInk(at: x, y) { return true }
            }
            return false
        }

        /// Scans a vertical column for any non-transparent pixels.
        func hasInkInColumn(_ x: Int, fromY: Int = 0, toY: Int? = nil) -> Bool {
            let maxY = toY ?? height
            for y in fromY ..< maxY {
                if hasInk(at: x, y) { return true }
            }
            return false
        }
    }

    // MARK: - Test Helpers

    /// Creates a minimal document with a single text node and renders it.
    private func renderTextNode(
        _ data: PenNode.TextData,
        rect: PenRect = PenRect(x: 0, y: 0, width: 200, height: 40),
        canvasSize: CGSize? = nil
    ) -> CGImage? {
        let node = PenNode(
            id: "text1",
            common: PenNodeCommon(),
            kind: .text(data)
        )
        let size = canvasSize ?? CGSize(width: Double(rect.width), height: Double(rect.height))
        let doc = PenDocument(version: "2.9", children: [node])
        let layoutRects: [String: PenRect] = [node.id: rect]
        return PenRenderer.render(doc, layoutRects: layoutRects, size: size)
    }

    // MARK: - Tests

    @Test("Plain text renders non-transparent pixels")
    func plainTextRendersPixels() throws {
        let data = PenNode.TextData(
            content: .literal("Hello"),
            fontSize: .literal(24),
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderTextNode(data))
        let reader = try #require(PixelReader(image))
        // Text should produce visible ink somewhere in the center area
        var foundInk = false
        for y in 5 ..< 35 {
            if reader.hasInkInRow(y, fromX: 5, toX: 100) {
                foundInk = true
                break
            }
        }
        #expect(foundInk, "Plain text should render visible pixels")
    }

    @Test("Center-aligned text has ink at horizontal center, not far left")
    func centerAlignedText() throws {
        let data = PenNode.TextData(
            content: .literal("Hi"),
            fontSize: .literal(20),
            textAlign: .center,
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderTextNode(
            data,
            rect: PenRect(x: 0, y: 0, width: 300, height: 40)
        ))
        let reader = try #require(PixelReader(image))
        // Center area (around x=150) should have ink
        var hasCenterInk = false
        for y in 5 ..< 35 {
            if reader.hasInkInRow(y, fromX: 120, toX: 180) {
                hasCenterInk = true
                break
            }
        }
        #expect(hasCenterInk, "Center-aligned text should have ink near horizontal center")

        // Far left (x=0..20) should be empty for short centered text
        var hasLeftInk = false
        for y in 0 ..< 40 {
            if reader.hasInkInRow(y, fromX: 0, toX: 20) {
                hasLeftInk = true
                break
            }
        }
        #expect(!hasLeftInk, "Center-aligned short text should not have ink at far left")
    }

    @Test("Vertically middle-aligned text has ink near vertical center")
    func verticalMiddleAlignment() throws {
        let data = PenNode.TextData(
            content: .literal("Mid"),
            fontSize: .literal(20),
            textAlignVertical: .middle,
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderTextNode(
            data,
            rect: PenRect(x: 0, y: 0, width: 200, height: 200)
        ))
        let reader = try #require(PixelReader(image))
        // Ink should be near the vertical center (around y=100), not near top
        var hasMiddleInk = false
        for y in 80 ..< 120 {
            if reader.hasInkInRow(y, fromX: 0, toX: 200) {
                hasMiddleInk = true
                break
            }
        }
        #expect(hasMiddleInk, "Middle-aligned text should have ink near vertical center")

        // Top area (y=0..30) should be empty
        var hasTopInk = false
        for y in 0 ..< 30 {
            if reader.hasInkInRow(y, fromX: 0, toX: 200) {
                hasTopInk = true
                break
            }
        }
        #expect(!hasTopInk, "Middle-aligned text should not have ink near the top")
    }

    @Test("Vertically bottom-aligned text has ink near bottom")
    func verticalBottomAlignment() throws {
        let data = PenNode.TextData(
            content: .literal("Bot"),
            fontSize: .literal(20),
            textAlignVertical: .bottom,
            fills: .single(.shorthand("#000000"))
        )
        let image = try #require(renderTextNode(
            data,
            rect: PenRect(x: 0, y: 0, width: 200, height: 200)
        ))
        let reader = try #require(PixelReader(image))
        // Ink should be near the bottom (y=170..200)
        var hasBottomInk = false
        for y in 170 ..< 200 {
            if reader.hasInkInRow(y, fromX: 0, toX: 200) {
                hasBottomInk = true
                break
            }
        }
        #expect(hasBottomInk, "Bottom-aligned text should have ink near the bottom")

        // Top area (y=0..30) should be empty
        var hasTopInk = false
        for y in 0 ..< 30 {
            if reader.hasInkInRow(y, fromX: 0, toX: 200) {
                hasTopInk = true
                break
            }
        }
        #expect(!hasTopInk, "Bottom-aligned text should not have ink near the top")
    }

    @Test("Text color comes from fills")
    func textColorFromFills() throws {
        let data = PenNode.TextData(
            content: .literal("Red"),
            fontSize: .literal(24),
            fills: .single(.shorthand("#FF0000"))
        )
        let image = try #require(renderTextNode(data))
        let reader = try #require(PixelReader(image))
        // Find any ink pixel and verify it's red
        var foundRedInk = false
        for y in 5 ..< 35 {
            for x in 5 ..< 100 {
                let (r, g, b, a) = reader.rgba(at: x, y)
                if a > 128, r > 200, g < 50, b < 50 {
                    foundRedInk = true
                    break
                }
            }
            if foundRedInk { break }
        }
        #expect(foundRedInk, "Text should render in the fill color (red)")
    }

    /// Pen draws a text with no fill as nothing (`render-text-unfilled.pen`); this test once
    /// pinned the black the renderer used to draw instead.
    @Test("Text with no fills draws nothing")
    func noFillsDrawsNothing() throws {
        let data = PenNode.TextData(
            content: .literal("Nothing"),
            fontSize: .literal(24)
        )
        let image = try #require(renderTextNode(data))
        let reader = try #require(PixelReader(image))
        var inked = 0
        for y in 0 ..< 40 {
            for x in 0 ..< 200 where reader.rgba(at: x, y).3 > 0 {
                inked += 1
            }
        }
        #expect(inked == 0, "\(inked) pixels drawn for text with no fills")
    }

    // MARK: - Empty Text Node Height

    @Test("Empty text node occupies one line height, not zero")
    func emptyTextNodeHeight() throws {
        // A text node with no content but fontSize=14 should still occupy
        // vertical space (approximately one line height). Pencil shows 0×18 for this.
        // Bug: layout engine returns 0 height for empty text, collapsing the node.
        let emptyNode = PenNode(
            id: "empty",
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(
                fontSize: .literal(14),
                fills: .single(.shorthand("#000000"))
            ))
        )
        let frame = PenNode(
            id: "frame",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                width: .fixed(200),
                height: .fixed(100),
                layout: .vertical,
                children: [emptyNode]
            ))
        )
        let doc = PenDocument(version: "2.9", children: [frame])
        let rects = PenLayoutEngine.layout(doc)
        let emptyRect = try #require(rects["empty"])

        // With the fix, the empty text node should have a non-zero height
        // based on font metrics (fontSize=14 → ~17-18px line height)
        #expect(emptyRect.height > 0, "Empty text node should have non-zero height")
        #expect(emptyRect.height >= 14, "Empty text node height should be at least font size")
        #expect(emptyRect.height < 30, "Empty text node height should be reasonable (not huge)")
        // Width should be zero since there's no content
        #expect(emptyRect.width == 0, "Empty text node should have zero width")
    }
}
