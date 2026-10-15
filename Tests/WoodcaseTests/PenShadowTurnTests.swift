import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A node's shadows turn and flip with it, as Pen draws them.
///
/// Pen's headless preview (pen CLI 0.3.11, 2026-10-15) of rects with a `0, 24` shadow: at
/// 90° the shadow falls on the right edge, at 180° above; a `flipY` sends it up, a `flipX`
/// left; a child of a frame turned 90° casts to the right; an inner shadow turns the same
/// way. CoreGraphics' own shadow offset ignores the CTM, so the renderer must carry the
/// offset through it.
struct PenShadowTurnTests {
    private static let canvas = CGSize(width: 100, height: 100)
    private static let red = PixelGrid.RGBA(r: 255, g: 0, b: 0, a: 255)
    private static let black = PixelGrid.RGBA(r: 0, g: 0, b: 0, a: 255)
    private static let white = PixelGrid.RGBA(r: 255, g: 255, b: 255, a: 255)

    private static func shadow(
        _ type: PenEffect.PenShadowEffect.ShadowType, _ color: String, x: Double, y: Double
    ) -> PenEffects {
        .single(.shadow(PenEffect.PenShadowEffect(
            shadowType: type, offset: PenEffect.PenOffset(x: .literal(x), y: .literal(y)),
            blur: .literal(0), color: .literal(color)
        )))
    }

    private static func render(_ nodes: [PenNode], _ rects: [String: PenRect]) throws -> PixelGrid {
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: nodes), layoutRects: rects, size: canvas
        ))
        return try #require(PixelGrid(image))
    }

    /// A 40-point square at the canvas's center casting a red `0, 20` outer shadow.
    private static func castingSquare(_ common: PenNodeCommon) throws -> PixelGrid {
        let card = PenNode(id: "card", common: common, kind: .rectangle(PenNode.RectangleData(
            fills: .single(.shorthand("#DDDDDD")), effects: shadow(.outer, "#FF0000FF", x: 0, y: 20)
        )))
        return try render([card], ["card": PenRect(x: 30, y: 30, width: 40, height: 40)])
    }

    @Test("An outer shadow turns with a node turned 90°: down becomes right")
    func outerShadowTurnsQuarter() throws {
        let pixels = try Self.castingSquare(PenNodeCommon(rotation: .literal(90)))
        #expect(pixels.pixel(80, 50) == Self.red, "right of the node: \(pixels.pixel(80, 50))")
        #expect(pixels.pixel(50, 80).a == 0, "nothing below: \(pixels.pixel(50, 80))")
    }

    @Test("An outer shadow turns with a node turned 180°: down becomes up")
    func outerShadowTurnsHalf() throws {
        let pixels = try Self.castingSquare(PenNodeCommon(rotation: .literal(180)))
        #expect(pixels.pixel(50, 20) == Self.red, "above the node: \(pixels.pixel(50, 20))")
        #expect(pixels.pixel(50, 80).a == 0, "nothing below: \(pixels.pixel(50, 80))")
    }

    @Test("An outer shadow flips with a vertically flipped node: down becomes up")
    func outerShadowFlips() throws {
        let pixels = try Self.castingSquare(PenNodeCommon(flipY: .literal(true)))
        #expect(pixels.pixel(50, 20) == Self.red, "above the node: \(pixels.pixel(50, 20))")
        #expect(pixels.pixel(50, 80).a == 0, "nothing below: \(pixels.pixel(50, 80))")
    }

    @Test("A child's outer shadow turns with its turned parent")
    func outerShadowTurnsWithAncestor() throws {
        let chip = PenNode(id: "chip", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(
            fills: .single(.shorthand("#DDDDDD")), effects: Self.shadow(.outer, "#FF0000FF", x: 0, y: 20)
        )))
        let holder = PenNode(
            id: "holder", common: PenNodeCommon(rotation: .literal(90)),
            kind: .frame(PenNode.FrameData(layout: PenLayoutDirection.none, children: [chip]))
        )
        let pixels = try Self.render([holder], [
            "holder": PenRect(x: 10, y: 10, width: 80, height: 80),
            "chip": PenRect(x: 25, y: 25, width: 30, height: 30),
        ])
        #expect(pixels.pixel(75, 50) == Self.red, "right of the child: \(pixels.pixel(75, 50))")
        #expect(pixels.pixel(50, 75).a == 0, "nothing below: \(pixels.pixel(50, 75))")
    }

    @Test("An inner shadow turns with its node: a 0, 20 offset at 90° shades the left edge")
    func innerShadowTurns() throws {
        let card = PenNode(
            id: "card", common: PenNodeCommon(rotation: .literal(90)),
            kind: .rectangle(PenNode.RectangleData(
                fills: .single(.shorthand("#FFFFFF")), effects: Self.shadow(.inner, "#000000FF", x: 0, y: 20)
            ))
        )
        let pixels = try Self.render([card], ["card": PenRect(x: 20, y: 20, width: 60, height: 60)])
        #expect(pixels.pixel(25, 50) == Self.black, "left inner edge: \(pixels.pixel(25, 50))")
        #expect(pixels.pixel(50, 25) == Self.white, "top inner edge: \(pixels.pixel(50, 25))")
    }

    @Test("A drawn silhouette's inner shadow turns with the context")
    func silhouetteInnerShadowTurns() throws {
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        // The renderer's y-down space, then a 90° turn about the canvas's center.
        context.translateBy(x: 0, y: 100)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 50, y: 50)
        context.rotate(by: .pi / 2)
        context.translateBy(x: -50, y: -50)
        let square = CGRect(x: 20, y: 20, width: 60, height: 60)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(square)
        let shadow = PenEffect.PenShadowEffect(
            shadowType: .inner, offset: PenEffect.PenOffset(x: .literal(0), y: .literal(20)),
            blur: .literal(0), color: .literal("#000000FF")
        )
        PenEffectRenderer.renderInnerShadow(shadow, bounds: square, in: context) { target in
            target.setFillColor(PenShadowSilhouette.ink)
            target.fill(square)
        }
        let image = try #require(context.makeImage())
        let pixels = try #require(PixelGrid(image))
        let turned = CGPoint(x: 50, y: 25).applying(
            CGAffineTransform(translationX: 50, y: 50).rotated(by: .pi / 2).translatedBy(x: -50, y: -50)
        )
        let shaded = pixels.pixel(Int(turned.x.rounded()), Int(turned.y.rounded()))
        #expect(shaded == Self.black, "the node's own top edge, wherever it turned to: \(shaded)")
        let opposite = pixels.pixel(100 - Int(turned.x.rounded()), 100 - Int(turned.y.rounded()))
        #expect(opposite == Self.white, "its own bottom edge: \(opposite)")
    }
}
