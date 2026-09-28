import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

struct PenRendererBackgroundBlurTests {
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

    private let canvasSize = CGSize(width: 100, height: 100)

    // MARK: - Test 1: Control (no background blur)

    @Test("Control: overlay without background blur shows overlay fill color")
    func controlNoBackgroundBlur() throws {
        let backdrop = PenNode(
            id: "backdrop",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let overlay = PenNode(
            id: "overlay",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#00FF00")),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let doc = PenDocument(version: "2.9", children: [backdrop, overlay])
        let rects: [String: PenRect] = [
            "backdrop": PenRect(x: 0, y: 0, width: 100, height: 100),
            "overlay": PenRect(x: 20, y: 20, width: 60, height: 60),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvasSize))
        let reader = try #require(PixelReader(image))

        let (r, g, _, _) = reader.rgba(at: 50, 50)
        #expect(g > 200, "Center should be green (overlay fill)")
        #expect(r < 50, "Center red channel should be low")

        let (or, og, _, oa) = reader.rgba(at: 10, 10)
        #expect(or > 200, "Outside overlay should be red (backdrop)")
        #expect(og < 50, "Outside overlay green channel should be low")
        #expect(oa == 255)
    }

    // MARK: - Test 2: Background blur softens backdrop

    /// Uses a two-tone backdrop: blue on the left half, red on the right half.
    /// The overlay (transparent, with background blur) straddles the boundary.
    /// With blur, the sharp color edge should be softened inside the overlay.
    @Test("Background blur softens the color boundary in backdrop")
    func backgroundBlurSoftensBackdrop() throws {
        let leftHalf = PenNode(
            id: "left",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let rightHalf = PenNode(
            id: "right",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let overlay = PenNode(
            id: "overlay",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#FFFFFF01")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(20)
                ))),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            "overlay": PenRect(x: 20, y: 20, width: 60, height: 60),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvasSize))
        let reader = try #require(PixelReader(image))

        // At the boundary (x=50) inside the overlay, without blur you'd see a sharp
        // edge: pure blue on the left, pure red on the right.
        // With blur(radius:20), the pixel at x=49 inside the overlay should have
        // a significant red component (blended from the red half).
        let (r, _, b, a) = reader.rgba(at: 49, 50)
        #expect(a > 0, "Inside overlay should have visible pixels from blurred backdrop")
        // Without blur, pixel at x=49 would be pure blue (r=0, b=255).
        // With blur, red channel should be significantly above 0 because the blur
        // mixes in the red from the right half.
        #expect(r > 40, "Blurred pixel near boundary should have red channel > 0 (mixed from red half)")
        // And blue should be reduced from pure 255 because it's mixed with red
        #expect(b < 220, "Blurred pixel near boundary should have reduced blue (mixed with red)")

        // Outside overlay, the sharp boundary should be preserved
        let (outR, _, outB, _) = reader.rgba(at: 49, 10)
        #expect(outR < 10, "Outside overlay at x=49 should be pure blue (no red)")
        #expect(outB > 250, "Outside overlay at x=49 should be pure blue")
    }

    // MARK: - Test 3: Clipping to node shape

    /// Uses a two-tone backdrop with a rounded-rect overlay with background blur.
    /// Pixels in the bounding-box corners (outside the rounded rect) should NOT
    /// be blurred — they should show the original sharp backdrop colors.
    @Test("Background blur is clipped to rounded rect shape")
    func backgroundBlurClipsToShape() throws {
        let leftHalf = PenNode(
            id: "left",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let rightHalf = PenNode(
            id: "right",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        // Rounded rect with large radius — corners are clipped
        let overlay = PenNode(
            id: "overlay",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                cornerRadius: .uniform(.literal(40)),
                fills: .single(.shorthand("#FFFFFF40")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(15)
                )))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            "overlay": PenRect(x: 10, y: 10, width: 80, height: 80),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvasSize))
        let reader = try #require(PixelReader(image))

        // Corner of the overlay's bounding box (11,11) should be OUTSIDE the
        // rounded rect shape, so blur should NOT apply there.
        // At (11,11) in the left half — should be pure blue without blur influence
        let (cornerR, _, cornerB, _) = reader.rgba(at: 11, 11)
        #expect(cornerR < 10, "Corner outside rounded rect should have no red (no blur bleed)")
        #expect(cornerB > 250, "Corner outside rounded rect should be pure blue")

        // Just inside the rounded rect shape, blur SHOULD apply.
        // At (45, 50) — inside the rounded rect and near the color boundary at x=50
        // (only 5 pixels away, well within blur radius 15)
        let (innerR, _, innerB, _) = reader.rgba(at: 45, 50)
        // With blur, the blue here should be mixed with some red from the right half
        #expect(innerR > 20, "Inside rounded rect near boundary should show blur mixing")
        #expect(innerB < 240, "Blue should be reduced by blur mixing")
    }

    // MARK: - Test 4: Zero radius is a no-op

    @Test("Background blur with zero radius is a no-op")
    func backgroundBlurZeroRadius() throws {
        let leftHalf = PenNode(
            id: "left",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let rightHalf = PenNode(
            id: "right",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let overlay = PenNode(
            id: "overlay",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#FFFFFF01")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(0)
                ))),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            "overlay": PenRect(x: 20, y: 20, width: 60, height: 60),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvasSize))
        let reader = try #require(PixelReader(image))

        // At x=49 inside overlay, without blur should be pure blue
        let (r, _, b, _) = reader.rgba(at: 49, 50)
        #expect(r < 10, "Zero-radius blur should NOT mix colors at boundary")
        #expect(b > 250, "Zero-radius blur should preserve pure blue at x=49")
    }

    // MARK: - Test 5: Disabled is a no-op

    @Test("Background blur with enabled=false is a no-op")
    func backgroundBlurDisabled() throws {
        let leftHalf = PenNode(
            id: "left",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let rightHalf = PenNode(
            id: "right",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let overlay = PenNode(
            id: "overlay",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#FFFFFF01")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    enabled: .literal(false),
                    radius: .literal(20)
                ))),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            "overlay": PenRect(x: 20, y: 20, width: 60, height: 60),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvasSize))
        let reader = try #require(PixelReader(image))

        let (r, _, b, _) = reader.rgba(at: 49, 50)
        #expect(r < 10, "Disabled blur should NOT mix colors at boundary")
        #expect(b > 250, "Disabled blur should preserve pure blue at x=49")
    }

    // MARK: - Test 6: Stacked with foreground blur

    @Test("Background blur coexists with foreground blur without crashing")
    func backgroundBlurWithForegroundBlur() throws {
        let leftHalf = PenNode(
            id: "left",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let rightHalf = PenNode(
            id: "right",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let overlay = PenNode(
            id: "overlay",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#00FF00")),
                effects: .multiple([
                    .backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                        radius: .literal(10)
                    )),
                    .blur(PenEffect.PenBlurEffect(
                        radius: .literal(4)
                    )),
                ]),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            "overlay": PenRect(x: 20, y: 20, width: 60, height: 60),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvasSize))
        let reader = try #require(PixelReader(image))

        let (_, _, _, a) = reader.rgba(at: 50, 50)
        #expect(a > 0, "Center should have visible pixels")

        // Foreground blur (sigma 2 pt) should bleed green just beyond the overlay rect
        let (_, fgG, _, fgA) = reader.rgba(at: 81, 50)
        #expect(fgA > 0, "Foreground blur should bleed beyond overlay bounds")
        #expect(fgG > 30, "Bled pixels should retain green channel")
    }

    // MARK: - Test 7: Nested background blur

    @Test("Nested background blur nodes render without crashing and soften further")
    func nestedBackgroundBlur() throws {
        let leftHalf = PenNode(
            id: "left",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let rightHalf = PenNode(
            id: "right",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let outerBlur = PenNode(
            id: "outerBlur",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#FFFFFF01")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(8)
                ))),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let innerBlur = PenNode(
            id: "innerBlur",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#FFFFFF01")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(12)
                ))),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, outerBlur, innerBlur])
        let rects: [String: PenRect] = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            "outerBlur": PenRect(x: 10, y: 10, width: 80, height: 80),
            "innerBlur": PenRect(x: 25, y: 25, width: 50, height: 50),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvasSize))
        let reader = try #require(PixelReader(image))

        // Inside the inner blur, at the color boundary, blur should mix colors
        let (r, _, b, a) = reader.rgba(at: 49, 50)
        #expect(a > 0, "Center should have visible pixels from nested blur")
        #expect(r > 20, "Nested blur should mix red into the boundary area")
        #expect(b < 240, "Nested blur should reduce blue at boundary")

        // Outside both blurs should preserve sharp boundary
        let (outR, _, outB, _) = reader.rgba(at: 49, 5)
        #expect(outR < 10, "Outside blurs should have sharp boundary (no red)")
        #expect(outB > 250, "Outside blurs should have pure blue")
    }

    // MARK: - Test 8: Graceful degradation on non-bitmap context

    @Test("Background blur gracefully no-ops on non-bitmap (PDF) context")
    func backgroundBlurOnPDFContext() {
        let leftHalf = PenNode(
            id: "left",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let rightHalf = PenNode(
            id: "right",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let overlay = PenNode(
            id: "overlay",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                fills: .single(.shorthand("#00FF00")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(20)
                ))),
                layout: PenLayoutDirection.none,
                children: []
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            "overlay": PenRect(x: 20, y: 20, width: 60, height: 60),
        ]

        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bgblur-test-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
        guard let consumer = CGDataConsumer(url: pdfURL as CFURL),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            Issue.record("Failed to create PDF context")
            return
        }

        pdfContext.translateBy(x: 0, y: 100)
        pdfContext.scaleBy(x: 1, y: -1)

        PenRenderer.render(doc, layoutRects: rects, into: pdfContext)

        #expect(Bool(true))
    }

    // MARK: - RapidPro Parity Tests

    // Ported from RapidPro's BackgroundBlurTests.swift to verify equivalent
    // behavior in the CG renderer.

    @Test("Background blur captures content behind it (RapidPro parity)")
    func capturesContent() throws {
        let leftHalf = PenNode(
            id: "redHalf",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let rightHalf = PenNode(
            id: "blueHalf",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let overlay = PenNode(
            id: "bgBlur",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FFFFFF01")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(8)
                )))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "redHalf": PenRect(x: 0, y: 0, width: 50, height: 100),
            "blueHalf": PenRect(x: 50, y: 0, width: 50, height: 100),
            "bgBlur": PenRect(x: 25, y: 25, width: 50, height: 50),
        ]
        let image = try #require(
            PenRenderer.render(doc, layoutRects: rects, size: CGSize(width: 100, height: 100))
        )
        let reader = try #require(PixelReader(image))

        // Center pixel (50, 50) should show blurred red+blue content
        let (r, _, b, a) = reader.rgba(at: 50, 50)
        let hasColor = r > 20 || b > 20
        #expect(hasColor, "Center should have blurred red/blue content, not be blank")
        #expect(a > 200, "Center should be mostly opaque from blur content")
    }

    @Test("Background blur respects corner radius clipping (RapidPro parity)")
    func respectsCornerRadius() throws {
        let leftHalf = PenNode(
            id: "redHalf",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FF0000"))
            ))
        )
        let rightHalf = PenNode(
            id: "blueHalf",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#0000FF"))
            ))
        )
        let overlay = PenNode(
            id: "bgBlurRounded",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(
                cornerRadius: .uniform(.literal(30)),
                fills: .single(.shorthand("#FFFFFF01")),
                effects: .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(
                    radius: .literal(5)
                )))
            ))
        )
        let doc = PenDocument(version: "2.9", children: [leftHalf, rightHalf, overlay])
        let rects: [String: PenRect] = [
            "redHalf": PenRect(x: 0, y: 0, width: 50, height: 100),
            "blueHalf": PenRect(x: 50, y: 0, width: 50, height: 100),
            "bgBlurRounded": PenRect(x: 10, y: 10, width: 80, height: 80),
        ]
        let image = try #require(
            PenRenderer.render(doc, layoutRects: rects, size: CGSize(width: 100, height: 100))
        )
        let reader = try #require(PixelReader(image))

        // Interior pixel at the red/blue boundary should show blurred content
        let (interiorR, _, interiorB, _) = reader.rgba(at: 50, 50)
        #expect(interiorR > 20 && interiorB > 20, "Interior should show blurred red+blue mix")

        // Corner pixel (11, 11) is inside the bounding box but outside the
        // rounded shape — should show raw red background, no blue blur bleed
        let (cornerR, _, cornerB, _) = reader.rgba(at: 11, 11)
        #expect(cornerR > 200, "Corner should show raw red background")
        #expect(cornerB < 30, "Corner should NOT have blue blur bleed")
    }
}
