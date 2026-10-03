import CoreGraphics
import Testing
@testable import Woodcase

struct PenImageFillTests {
    // MARK: - Helpers

    /// Creates a solid-color test image of the given size.
    private func makeTestImage(
        width: Int, height: Int,
        r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255
    ) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        let color = CGColor(
            colorSpace: colorSpace,
            components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, CGFloat(a) / 255]
        )!
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

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

    /// Renders a single rectangle node with an image fill using the given provider.
    private func renderWithImageFill(
        url: String = "test://image.png",
        mode: PenImageFillMode? = nil,
        enabled: PenValue<Bool>? = nil,
        opacity: PenValue<Double>? = nil,
        blendMode: PenBlendMode? = nil,
        additionalFills: [PenFill] = [],
        canvasSize: CGSize = CGSize(width: 100, height: 100),
        imageProvider: @escaping PenRenderer.ImageProvider
    ) -> CGImage? {
        let imageFill = PenFill.image(PenFill.PenImageFill(
            enabled: enabled,
            blendMode: blendMode,
            opacity: opacity,
            url: url,
            mode: mode
        ))
        let fills: PenFills = if additionalFills.isEmpty {
            .single(imageFill)
        } else {
            .multiple(additionalFills + [imageFill])
        }
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: fills))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let rects: [String: PenRect] = [
            "rect1": PenRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height),
        ]
        return PenRenderer.render(
            doc, layoutRects: rects, size: canvasSize,
            imageProvider: imageProvider
        )
    }

    // MARK: - Tests

    @Test("Image fill stretch mode fills entire shape bounds")
    func stretchMode() throws {
        let testImage = makeTestImage(width: 40, height: 20, r: 0, g: 128, b: 255)
        let image = try #require(renderWithImageFill(mode: .stretch) { _ in testImage })
        let reader = try #require(PixelReader(image))
        // Center should have the test image color (stretched to fill 100x100)
        #expect(reader.matches(at: 50, 50, r: 0, g: 128, b: 255, a: 255))
        // Corners should also be filled (stretch covers everything)
        #expect(reader.matches(at: 5, 5, r: 0, g: 128, b: 255, a: 255))
        #expect(reader.matches(at: 95, 95, r: 0, g: 128, b: 255, a: 255))
    }

    @Test("Image fill cover mode covers bounds with aspect-fill (no letterbox)")
    func fillMode() throws {
        // Wide image (200x50) into square (100x100) — aspect-fill scales to cover
        let testImage = makeTestImage(width: 200, height: 50, r: 255, g: 0, b: 128)
        let image = try #require(renderWithImageFill(mode: .cover) { _ in testImage })
        let reader = try #require(PixelReader(image))
        // Center should have image color
        #expect(reader.matches(at: 50, 50, r: 255, g: 0, b: 128, a: 255))
        // Edges should also be covered (no transparent letterbox)
        #expect(reader.matches(at: 5, 50, r: 255, g: 0, b: 128, a: 255))
        #expect(reader.matches(at: 95, 50, r: 255, g: 0, b: 128, a: 255))
    }

    @Test("Image fill contain mode fits within bounds with transparent padding")
    func fitMode() throws {
        // Wide image (200x50) into square (100x100) — aspect-fit: image is 100x25, centered
        let testImage = makeTestImage(width: 200, height: 50, r: 128, g: 255, b: 0)
        let image = try #require(renderWithImageFill(mode: .contain) { _ in testImage })
        let reader = try #require(PixelReader(image))
        // Center should have image color
        #expect(reader.matches(at: 50, 50, r: 128, g: 255, b: 0, a: 255))
        // Top edge (vertical letterbox region) should be transparent
        let (_, _, _, topA) = reader.rgba(at: 50, 5)
        #expect(topA == 0)
        // Bottom edge should also be transparent
        let (_, _, _, bottomA) = reader.rgba(at: 50, 95)
        #expect(bottomA == 0)
    }

    @Test("Image fill with nil provider skips fill")
    func nilProvider() throws {
        let image = try #require(renderWithImageFill { _ in nil })
        let reader = try #require(PixelReader(image))
        // Should be transparent — no image returned
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a == 0)
    }

    @Test("Image fill with 50% opacity renders semi-transparent")
    func imageOpacity() throws {
        let testImage = makeTestImage(width: 100, height: 100, r: 0, g: 128, b: 255)
        let image = try #require(renderWithImageFill(
            opacity: .literal(0.5)
        ) { _ in testImage })
        let reader = try #require(PixelReader(image))
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        // Alpha should be roughly 128 (50% of 255)
        #expect(a > 100)
        #expect(a < 160)
    }

    @Test("Image fill with multiply blend mode blends correctly")
    func imageBlendMode() throws {
        // White image with multiply over red base → should show red
        let whiteImage = makeTestImage(width: 100, height: 100, r: 255, g: 255, b: 255)
        let image = try #require(renderWithImageFill(
            blendMode: .multiply,
            additionalFills: [.shorthand("#FF0000")],
            imageProvider: { _ in whiteImage }
        ))
        let reader = try #require(PixelReader(image))
        // Multiply white * red = red
        #expect(reader.matches(at: 50, 50, r: 255, g: 0, b: 0, a: 255, tolerance: 5))
    }

    @Test("Disabled image fill is skipped")
    func disabledImageFill() throws {
        let testImage = makeTestImage(width: 100, height: 100, r: 255, g: 0, b: 0)
        let image = try #require(renderWithImageFill(
            enabled: .literal(false)
        ) { _ in testImage })
        let reader = try #require(PixelReader(image))
        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a == 0)
    }

    @Test("Image fill stacks on top of solid color fill")
    func stackedFills() throws {
        // Red base fill + green image on top → center should be green
        let greenImage = makeTestImage(width: 100, height: 100, r: 0, g: 200, b: 0)
        let image = try #require(renderWithImageFill(
            additionalFills: [.shorthand("#FF0000")],
            imageProvider: { _ in greenImage }
        ))
        let reader = try #require(PixelReader(image))
        // Green image on top covers the red base
        #expect(reader.matches(at: 50, 50, r: 0, g: 200, b: 0, a: 255))
    }
}
