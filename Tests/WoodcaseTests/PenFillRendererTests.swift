import CoreGraphics
import Testing
@testable import Woodcase

/// Tests for gradient fill rendering.
/// Reference pixel values were generated from Pencil fixture render-gradients.pen
/// using scripts/probe-pixels.swift on the @2x exported PNGs.
struct PenFillRendererTests {
    // MARK: - Pixel Reading Helper

    private struct PixelReader {
        let data: [UInt8]
        let width: Int
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

        func matches(at x: Int, _ y: Int, r: UInt8, g: UInt8, b: UInt8, tolerance: UInt8 = 10) -> Bool {
            let (pr, pg, pb, _) = rgba(at: x, y)
            return abs(Int(pr) - Int(r)) <= Int(tolerance)
                && abs(Int(pg) - Int(g)) <= Int(tolerance)
                && abs(Int(pb) - Int(b)) <= Int(tolerance)
        }
    }

    // MARK: - Test Helpers

    /// Renders a rectangle with the given fills and dimensions.
    private func renderRect(fills: PenFills, width: Int = 120, height: Int = 120) -> CGImage? {
        let node = PenNode(
            id: "rect1",
            common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: fills))
        )
        let doc = PenDocument(version: "2.9", children: [node])
        let w = CGFloat(width)
        let h = CGFloat(height)
        return PenRenderer.render(
            doc,
            layoutRects: ["rect1": PenRect(x: 0, y: 0, width: Double(width), height: Double(height))],
            size: CGSize(width: w, height: h)
        )
    }

    // MARK: - Linear Gradient

    @Test("Linear gradient top-to-bottom: top is blue, bottom is red")
    func linearTopToBottom() throws {
        // Matches Pencil fixture: linear gradient rotation=0, red(pos 0) at bottom, blue(pos 1) at top
        // Pencil reference: top≈(32,0,222), bottom≈(223,0,31)
        let fills: PenFills = .single(.gradient(PenFill.PenGradientFill(
            gradientType: .linear,
            size: PenFill.PenFillSize(height: .literal(1)),
            rotation: .literal(0),
            colors: [
                PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
            ]
        )))
        let image = try #require(renderRect(fills: fills))
        let reader = try #require(PixelReader(image))
        let (tr, _, tb, _) = reader.rgba(at: 60, 15) // top quarter
        let (br, _, bb, _) = reader.rgba(at: 60, 105) // bottom quarter
        // Top should be more blue than red
        #expect(tb > tr)
        // Bottom should be more red than blue
        #expect(br > bb)
    }

    @Test("Linear gradient left-to-right (rotation=90)")
    func linearLeftToRight() throws {
        let fills: PenFills = .single(.gradient(PenFill.PenGradientFill(
            gradientType: .linear,
            size: PenFill.PenFillSize(height: .literal(1)),
            rotation: .literal(90),
            colors: [
                PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
            ]
        )))
        let image = try #require(renderRect(fills: fills))
        let reader = try #require(PixelReader(image))
        // Center should be opaque (gradient actually rendered)
        let (_, _, _, ca) = reader.rgba(at: 60, 60)
        #expect(ca == 255)
        // Center vertically: top and bottom should be same (horizontal gradient)
        let (tr, _, tb, _) = reader.rgba(at: 60, 15)
        let (br, _, bb, _) = reader.rgba(at: 60, 105)
        // Both should be roughly equal (midpoint of horizontal gradient)
        #expect(abs(Int(tr) - Int(br)) < 20)
        #expect(abs(Int(tb) - Int(bb)) < 20)
        // Pencil convention: rotation=90 puts stop 0 (red) on the right
        let (lr, _, lb, _) = reader.rgba(at: 15, 60)
        let (rr, _, rb, _) = reader.rgba(at: 105, 60)
        #expect(rr > lr) // Right is redder (stop 0)
        #expect(lb > rb) // Left is bluer (stop 1)
    }

    @Test("Linear gradient with 3 stops: midpoint is yellow")
    func linear3Stop() throws {
        // Red → Yellow → Blue. Midpoint should be yellow.
        // Pencil reference: mid ≈ (255,253,0)
        let fills: PenFills = .single(.gradient(PenFill.PenGradientFill(
            gradientType: .linear,
            size: PenFill.PenFillSize(height: .literal(1)),
            rotation: .literal(0),
            colors: [
                PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#FFFF00"), position: .literal(0.5)),
                PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
            ]
        )))
        let image = try #require(renderRect(fills: fills))
        let reader = try #require(PixelReader(image))
        // Midpoint should be yellow-ish
        let (r, g, b, _) = reader.rgba(at: 60, 60)
        #expect(r > 200)
        #expect(g > 200)
        #expect(b < 50)
    }

    // MARK: - Radial Gradient

    @Test("Radial gradient: center is white, edge is dark")
    func radialGradient() throws {
        // White center → Black edge
        // Pencil reference: center ≈ (253,253,253), mid ≈ (128,128,128)
        let fills: PenFills = .single(.gradient(PenFill.PenGradientFill(
            gradientType: .radial,
            size: PenFill.PenFillSize(width: .literal(1), height: .literal(1)),
            colors: [
                PenFill.PenGradientStop(color: .literal("#FFFFFF"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#000000"), position: .literal(1)),
            ]
        )))
        let image = try #require(renderRect(fills: fills))
        let reader = try #require(PixelReader(image))
        // Center should be bright
        let (cr, cg, cb, _) = reader.rgba(at: 60, 60)
        #expect(cr > 200)
        #expect(cg > 200)
        #expect(cb > 200)
        // Edge should be darker
        let (er, eg, eb, _) = reader.rgba(at: 5, 60)
        #expect(er < cr)
        #expect(eg < cg)
        #expect(eb < cb)
    }

    // MARK: - Angular Gradient

    @Test("Angular gradient renders non-uniform colors around center")
    func angularGradient() throws {
        // Red → Green → Blue → Red
        let fills: PenFills = .single(.gradient(PenFill.PenGradientFill(
            gradientType: .angular,
            size: PenFill.PenFillSize(width: .literal(1), height: .literal(1)),
            colors: [
                PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#00FF00"), position: .literal(0.33)),
                PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(0.66)),
                PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(1)),
            ]
        )))
        let image = try #require(renderRect(fills: fills))
        let reader = try #require(PixelReader(image))
        // Just verify it rendered something non-uniform: check opposite edges differ
        let left = reader.rgba(at: 5, 60)
        let right = reader.rgba(at: 115, 60)
        let top = reader.rgba(at: 60, 5)
        // At least two of these should differ significantly
        let diffLR = abs(Int(left.0) - Int(right.0)) + abs(Int(left.1) - Int(right.1)) + abs(Int(left.2) - Int(right.2))
        let diffLT = abs(Int(left.0) - Int(top.0)) + abs(Int(left.1) - Int(top.1)) + abs(Int(left.2) - Int(top.2))
        #expect(diffLR > 50 || diffLT > 50)
    }

    // MARK: - Gradient with Opacity

    @Test("Gradient with opacity shows base fill through")
    func gradientWithOpacity() throws {
        // Green base + 50% opacity red→blue gradient
        // Pencil reference: mid ≈ (64,127,63)
        let fills: PenFills = .multiple([
            .shorthand("#00FF00"),
            .gradient(PenFill.PenGradientFill(
                gradientType: .linear,
                opacity: .literal(0.5),
                size: PenFill.PenFillSize(height: .literal(1)),
                rotation: .literal(0),
                colors: [
                    PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
                    PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
                ]
            )),
        ])
        let image = try #require(renderRect(fills: fills))
        let reader = try #require(PixelReader(image))
        // Center should have green showing through (g > 0)
        let (r, g, b, _) = reader.rgba(at: 60, 60)
        #expect(g > 50) // Green base visible
        // Should be a blend — not pure green, not pure gradient
        #expect(r > 10 || b > 10)
    }

    // MARK: - Gradient with Blend Mode

    @Test("Gradient with multiply blend mode darkens base fill")
    func gradientWithBlendMode() throws {
        // Red base + white→blue gradient with multiply
        // Multiply: red × white = red (top), red × blue ≈ black (bottom)
        // Pencil reference: top ≈ (21,0,0), mid ≈ (128,0,0), bottom ≈ (234,0,0)
        let fills: PenFills = .multiple([
            .shorthand("#FF0000"),
            .gradient(PenFill.PenGradientFill(
                blendMode: .multiply,
                gradientType: .linear,
                size: PenFill.PenFillSize(height: .literal(1)),
                rotation: .literal(0),
                colors: [
                    PenFill.PenGradientStop(color: .literal("#FFFFFF"), position: .literal(0)),
                    PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
                ]
            )),
        ])
        let image = try #require(renderRect(fills: fills))
        let reader = try #require(PixelReader(image))
        // Bottom should be brighter red (white × red = red)
        let (br, _, _, _) = reader.rgba(at: 60, 105)
        // Top should be darker (blue × red ≈ 0)
        let (tr, _, _, _) = reader.rgba(at: 60, 15)
        #expect(br > tr) // Bottom brighter than top
    }

    // MARK: - Rotated Gradient on Non-Square Rect

    @Test("Linear gradient 90deg on non-square rect spans full width")
    func linearGradient90DegNonSquare() throws {
        // On a 120×60 rect with rotation=90, the gradient should span the width (120px).
        // Bug: halfLength used bounds.height (60), so the gradient only covered 60px
        // centered on a 120px-wide rect — x=30 would be at the gradient edge.
        // Fix: halfLength should use width at 90deg, so x=30 is at ~25% interpolation.
        let fills: PenFills = .single(.gradient(PenFill.PenGradientFill(
            gradientType: .linear,
            size: PenFill.PenFillSize(height: .literal(1)),
            rotation: .literal(90),
            colors: [
                PenFill.PenGradientStop(color: .literal("#FF6600"), position: .literal(0)),
                PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
            ]
        )))
        let image = try #require(renderRect(fills: fills, width: 120, height: 60))
        let reader = try #require(PixelReader(image))
        // Pencil convention: rotation=90 puts stop 0 (orange) on the right.
        // At x=90 (three-quarter width), we should be well into the orange zone.
        let (r90, _, b90, _) = reader.rgba(at: 90, 30)
        // At x=30 (quarter width), we should be well into the blue zone.
        let (r30, _, b30, _) = reader.rgba(at: 30, 30)
        // Right side should be more orange than left
        #expect(r90 > r30, "Right side should be more orange (stop 0)")
        // Left side should be more blue than right
        #expect(b30 > b90, "Left side should be more blue (stop 1)")
        // The key assertion: at x=30, with the bug the gradient only spans 60px
        // so x=30 is at the very edge and would be nearly pure blue (b > 240).
        // With the fix, x=30 is at ~25% interpolation, so blue should be moderated.
        #expect(b30 < 240, "Quarter-width pixel should be interpolated, not at gradient edge")
    }
}
