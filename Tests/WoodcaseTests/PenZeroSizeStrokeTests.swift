//
//  PenZeroSizeStrokeTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Testing
@testable import Woodcase

/// A stroke on a box that is a point — a sizeless `layout: "none"` frame settles at 0×0 —
/// still paints its band around the point, as Pen paints it (`render-sizeless-frames.pen`,
/// board `paint`: an 8 pt outer stroke is a 16×16 square about the frame's point, and its
/// outer shadow is cast by that square). Core Graphics strokes nothing along a path of no
/// length, so the band is laid out from the box instead (leaf Jg0BOv).
struct PenZeroSizeStrokeTests {
    /// The canvas, in points and pixels.
    private static let canvas = 100

    /// A frame with no children, its stroke and effects as given, at 0×0 on (50, 50).
    private func pointFrame(alignment: PenStrokeAlign, effects: PenEffects? = nil) -> PenNode {
        PenNode(
            id: "point",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(
                stroke: .single(.shorthand("#FF0000")),
                strokeWidth: .uniform(.literal(8)),
                strokeAlignment: alignment,
                effects: effects
            ))
        )
    }

    /// Each pixel's alpha, row by row, after rendering `node` at (50, 50), 0×0.
    private func alphas(_ node: PenNode) throws -> [UInt8] {
        let doc = PenDocument(version: "2.17", children: [node])
        let image = try #require(PenRenderer.render(
            doc, layoutRects: [node.id: PenRect(x: 50, y: 50, width: 0, height: 0)],
            size: CGSize(width: Self.canvas, height: Self.canvas)
        ))
        var pixels = [UInt8](repeating: 0, count: Self.canvas * Self.canvas * 4)
        let context = try #require(CGContext(
            data: &pixels, width: Self.canvas, height: Self.canvas, bitsPerComponent: 8,
            bytesPerRow: Self.canvas * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: Self.canvas, height: Self.canvas))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// Whether the pixel whose top-left corner is (x, y) is painted.
    private func painted(_ alphas: [UInt8], _ x: Int, _ y: Int) -> Bool {
        alphas[y * Self.canvas + x] > 128
    }

    @Test("An outer stroke on a 0×0 box is a square twice its width about the point")
    func outerStrokeIsASquare() throws {
        let alphas = try alphas(pointFrame(alignment: .outer))
        #expect(painted(alphas, 42, 42))
        #expect(painted(alphas, 57, 57))
        #expect(painted(alphas, 50, 50))
        #expect(!painted(alphas, 40, 50))
        #expect(!painted(alphas, 59, 50))
    }

    @Test("A centred stroke on a 0×0 box is a square its own width about the point")
    func centredStrokeIsASquare() throws {
        let alphas = try alphas(pointFrame(alignment: .center))
        #expect(painted(alphas, 46, 46))
        #expect(painted(alphas, 53, 53))
        #expect(!painted(alphas, 44, 50))
        #expect(!painted(alphas, 55, 50))
    }

    @Test("An outer shadow on a 0×0 box is cast by its stroke's square")
    func shadowIsCastByTheStroke() throws {
        let shadow = PenEffect.shadow(PenEffect.PenShadowEffect(
            shadowType: .outer, offset: PenEffect.PenOffset(x: .literal(20), y: .literal(20)),
            blur: .literal(0), color: .literal("#0000FFFF")
        ))
        let alphas = try alphas(pointFrame(alignment: .outer, effects: .single(shadow)))
        #expect(painted(alphas, 72, 72))
        #expect(!painted(alphas, 80, 80))
    }
}
