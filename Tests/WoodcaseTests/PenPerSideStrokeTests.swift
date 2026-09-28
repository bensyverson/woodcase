import CoreGraphics
import Testing
@testable import Woodcase

/// Tests for per-side stroke rendering.
///
/// Per-side strokes allow each edge (top, right, bottom, left) to have its own
/// thickness. A nil or zero thickness means no stroke on that edge.
struct PenPerSideStrokeTests {
    // MARK: - Pixel Reading Helper

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

        /// Returns true if the pixel has significant red (stroke color #FF0000).
        func hasStroke(at x: Int, _ y: Int) -> Bool {
            let (r, g, b, a) = rgba(at: x, y)
            return a > 128 && r > 200 && g < 50 && b < 50
        }

        /// Returns true if the pixel does not contain the red stroke color.
        func hasNoStroke(at x: Int, _ y: Int) -> Bool {
            !hasStroke(at: x, y)
        }
    }

    // MARK: - Helpers

    private func renderSingleNode(
        _ node: PenNode,
        rect: PenRect = PenRect(x: 0, y: 0, width: 100, height: 100),
        canvasSize: CGSize = CGSize(width: 100, height: 100)
    ) -> CGImage? {
        let doc = PenDocument(version: "2.9", children: [node])
        let layoutRects: [String: PenRect] = [node.id: rect]
        return PenRenderer.render(doc, layoutRects: layoutRects, size: canvasSize)
    }

    private func makeRect(
        strokeWidth: PenStrokeWidth,
        stroke: PenFills? = .single(.shorthand("#FF0000")),
        fills: PenFills? = .single(.shorthand("#FFFFFF"))
    ) -> PenNode {
        PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: fills,
                stroke: stroke,
                strokeWidth: strokeWidth
            ))
        )
    }

    private func makeFrame(
        strokeWidth: PenStrokeWidth,
        stroke: PenFills? = .single(.shorthand("#FF0000")),
        fills: PenFills? = .single(.shorthand("#FFFFFF"))
    ) -> PenNode {
        PenNode(
            id: "frame1",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: fills,
                stroke: stroke,
                strokeWidth: strokeWidth
            ))
        )
    }

    // MARK: - Bottom-only stroke

    @Test("Rectangle with bottom-only per-side stroke draws only on bottom edge")
    func bottomOnlyStrokeOnRect() throws {
        let node = makeRect(
            strokeWidth: .perSide(PenStrokeWidth.Sides(top: nil, right: nil, bottom: .literal(4), left: nil))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))

        // Bottom edge (inside, 2px from bottom) should have red stroke
        #expect(reader.hasStroke(at: 50, 98), "Bottom edge should have stroke")

        // Top edge should NOT have stroke
        #expect(reader.hasNoStroke(at: 50, 1), "Top edge should not have stroke")

        // Left edge should NOT have stroke
        #expect(reader.hasNoStroke(at: 1, 50), "Left edge should not have stroke")

        // Right edge should NOT have stroke
        #expect(reader.hasNoStroke(at: 98, 50), "Right edge should not have stroke")
    }

    @Test("Frame with bottom-only per-side stroke draws only on bottom edge")
    func bottomOnlyStrokeOnFrame() throws {
        let node = makeFrame(
            strokeWidth: .perSide(PenStrokeWidth.Sides(top: nil, right: nil, bottom: .literal(4), left: nil))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))

        // Bottom edge should have stroke
        #expect(reader.hasStroke(at: 50, 98), "Bottom edge should have stroke")

        // Other edges should NOT
        #expect(reader.hasNoStroke(at: 50, 1), "Top edge should not have stroke")
        #expect(reader.hasNoStroke(at: 1, 50), "Left edge should not have stroke")
        #expect(reader.hasNoStroke(at: 98, 50), "Right edge should not have stroke")
    }

    // MARK: - Top-only stroke

    @Test("Rectangle with top-only per-side stroke draws only on top edge")
    func topOnlyStroke() throws {
        let node = makeRect(
            strokeWidth: .perSide(PenStrokeWidth.Sides(top: .literal(4), right: nil, bottom: nil, left: nil))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))

        // Top edge should have stroke
        #expect(reader.hasStroke(at: 50, 1), "Top edge should have stroke")

        // Bottom edge should NOT
        #expect(reader.hasNoStroke(at: 50, 98), "Bottom edge should not have stroke")
    }

    // MARK: - Mixed per-side stroke

    @Test("Per-side stroke with different thicknesses on each side")
    func mixedPerSideStroke() throws {
        let node = makeRect(
            strokeWidth: .perSide(PenStrokeWidth.Sides(
                top: .literal(6),
                right: nil,
                bottom: .literal(6),
                left: nil
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))

        // Top and bottom should have stroke
        #expect(reader.hasStroke(at: 50, 2), "Top edge should have stroke")
        #expect(reader.hasStroke(at: 50, 97), "Bottom edge should have stroke")

        // Left and right should NOT
        #expect(reader.hasNoStroke(at: 1, 50), "Left edge should not have stroke")
        #expect(reader.hasNoStroke(at: 98, 50), "Right edge should not have stroke")
    }

    // MARK: - Zero thickness sides

    @Test("Per-side stroke with explicit zero thickness is not drawn")
    func zeroThicknessSideNotDrawn() throws {
        let node = makeRect(
            strokeWidth: .perSide(PenStrokeWidth.Sides(
                top: .literal(0),
                right: .literal(0),
                bottom: .literal(4),
                left: .literal(0)
            ))
        )
        let image = try #require(renderSingleNode(node))
        let reader = try #require(PixelReader(image))

        // Only bottom should have stroke
        #expect(reader.hasStroke(at: 50, 98), "Bottom edge should have stroke")
        #expect(reader.hasNoStroke(at: 50, 1), "Top edge should not have stroke")
        #expect(reader.hasNoStroke(at: 1, 50), "Left edge should not have stroke")
        #expect(reader.hasNoStroke(at: 98, 50), "Right edge should not have stroke")
    }
}
