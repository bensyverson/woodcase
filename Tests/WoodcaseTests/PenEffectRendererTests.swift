import CoreGraphics
import Testing
@testable import Woodcase

struct PenEffectRendererTests {
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
    }

    // MARK: - Test Helpers

    private func renderSingleNode(
        _ node: PenNode,
        rect: PenRect = PenRect(x: 0, y: 0, width: 100, height: 100),
        canvasSize: CGSize = CGSize(width: 100, height: 100)
    ) -> CGImage? {
        let doc = PenDocument(version: "2.9", children: [node])
        let layoutRects: [String: PenRect] = [node.id: rect]
        return PenRenderer.render(doc, layoutRects: layoutRects, size: canvasSize)
    }

    // MARK: - Outer Shadow

    @Test("Outer shadow produces pixels outside the shape")
    func outerShadow() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FFFFFF")),
                effects: .single(.shadow(PenEffect.PenShadowEffect(
                    shadowType: .outer,
                    offset: PenEffect.PenOffset(x: .literal(4), y: .literal(4)),
                    blur: .literal(8),
                    color: .literal("#00000080")
                )))
            ))
        )
        let image = try #require(renderSingleNode(
            node,
            rect: PenRect(x: 10, y: 10, width: 60, height: 60)
        ))
        let reader = try #require(PixelReader(image))
        // Outside the rect (beyond x=70, y=70) should have shadow pixels
        // Shadow offset is (4,4) with blur 8, so shadow extends beyond the shape
        let (_, _, _, a) = reader.rgba(at: 78, 78)
        #expect(a > 0, "Outer shadow should produce visible pixels outside the shape")
    }

    // MARK: - Inner Shadow

    @Test("Inner shadow darkens edge pixels compared to center")
    func innerShadow() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FFFFFF")),
                effects: .single(.shadow(PenEffect.PenShadowEffect(
                    shadowType: .inner,
                    offset: PenEffect.PenOffset(x: .literal(2), y: .literal(2)),
                    blur: .literal(6),
                    color: .literal("#00000080")
                )))
            ))
        )
        let image = try #require(renderSingleNode(
            node,
            rect: PenRect(x: 10, y: 10, width: 80, height: 80)
        ))
        let reader = try #require(PixelReader(image))
        // Center should be bright white (fill color, minimal shadow)
        let (centerR, centerG, centerB, _) = reader.rgba(at: 50, 50)
        let centerBrightness = Int(centerR) + Int(centerG) + Int(centerB)
        // Shadow offset (2,2) in .pen coordinates means the shadow is cast
        // toward the bottom-right, which darkens the top-left inside edge
        let (edgeR, edgeG, edgeB, _) = reader.rgba(at: 12, 12)
        let edgeBrightness = Int(edgeR) + Int(edgeG) + Int(edgeB)
        #expect(edgeBrightness < centerBrightness, "Inner shadow should darken edge pixels relative to center")
    }

    // MARK: - Blur

    @Test("Blur bleeds color outside the original shape boundary")
    func blurEffect() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000")),
                effects: .single(.blur(PenEffect.PenBlurEffect(
                    radius: .literal(4)
                )))
            ))
        )
        let image = try #require(renderSingleNode(
            node,
            rect: PenRect(x: 20, y: 20, width: 60, height: 60)
        ))
        let reader = try #require(PixelReader(image))
        // Just outside the rect boundary (e.g. x=82, y=50) should have some
        // red bleed from the blur
        let (r, _, _, a) = reader.rgba(at: 83, 50)
        #expect(a > 0, "Blur should bleed pixels outside the original shape boundary")
        #expect(r > 100, "Blurred pixels outside red rect should have red channel")
    }

    // MARK: - Multiple Effects

    @Test("Multiple effects are all applied")
    func multipleEffects() throws {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000")),
                effects: .multiple([
                    .shadow(PenEffect.PenShadowEffect(
                        shadowType: .outer,
                        offset: PenEffect.PenOffset(x: .literal(6), y: .literal(6)),
                        blur: .literal(4),
                        color: .literal("#00000080")
                    )),
                    .blur(PenEffect.PenBlurEffect(
                        radius: .literal(2)
                    )),
                ])
            ))
        )
        let image = try #require(renderSingleNode(
            node,
            rect: PenRect(x: 10, y: 10, width: 50, height: 50)
        ))
        let reader = try #require(PixelReader(image))
        // Blur (sigma 1 pt) should bleed the red fill just outside the rect boundary
        let (r, _, _, blurA) = reader.rgba(at: 60, 35)
        #expect(blurA > 0, "Blur from multiple effects should bleed color outside rect")
        #expect(r > 50, "Blurred bleed should retain red channel")
        // Shadow should be visible — check just past the shape edge + offset
        // Shape is at (10,10) 50x50, shadow offset is (6,6)
        // So shadow center is offset from shape edge: x=60+6=66, y=60+6=66
        let (_, _, _, shadowA) = reader.rgba(at: 64, 64)
        #expect(shadowA > 0, "Outer shadow from multiple effects should produce visible pixels")
    }
}
