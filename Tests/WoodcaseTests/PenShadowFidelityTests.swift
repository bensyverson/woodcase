import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Where shadows sit in Pen's paint order, and what casts them.
///
/// Pen 1.2.14 paints a node's outer shadows first, then its fills, its inner shadows, its
/// stroke and last its children. An outer shadow is cast by the node's silhouette — its
/// shape and stroke, whatever the paint's alpha, not its children — and never shows through
/// the node itself. Every shadow in the `effect` array is drawn.
struct PenShadowFidelityTests {
    private static let canvas = CGSize(width: 100, height: 100)

    private static func shadow(
        _ type: PenEffect.PenShadowEffect.ShadowType, _ color: String, x: Double, y: Double, blur: Double
    ) -> PenEffect {
        .shadow(PenEffect.PenShadowEffect(
            shadowType: type, offset: PenEffect.PenOffset(x: .literal(x), y: .literal(y)),
            blur: .literal(blur), color: .literal(color)
        ))
    }

    private static func render(_ nodes: [PenNode], _ rects: [String: PenRect]) throws -> PixelGrid {
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: nodes), layoutRects: rects, size: canvas
        ))
        return try #require(PixelGrid(image))
    }

    @Test("An inner shadow sits under the stroke")
    func innerShadowUnderStroke() throws {
        var card = PenNode.RectangleData(
            fills: .single(.shorthand("#FFFFFF")),
            effects: .single(Self.shadow(.inner, "#000000FF", x: 6, y: 6, blur: 8))
        )
        card.stroke = .single(.shorthand("#0000FF"))
        card.strokeWidth = .uniform(.literal(8))
        card.strokeAlignment = .inner
        let pixels = try Self.render(
            [PenNode(id: "card", common: PenNodeCommon(), kind: .rectangle(card))],
            ["card": PenRect(x: 20, y: 20, width: 60, height: 60)]
        )
        let band = pixels.pixel(23, 50)
        #expect(band == PixelGrid.RGBA(r: 0, g: 0, b: 255, a: 255), "the stroke is untouched; got \(band)")
    }

    @Test("An inner shadow sits under the children")
    func innerShadowUnderChildren() throws {
        let chip = PenNode(
            id: "chip", common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FF8800"))))
        )
        let card = PenNode(id: "card", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(
            fills: .single(.shorthand("#FFFFFF")),
            effects: .single(Self.shadow(.inner, "#000000FF", x: 0, y: 0, blur: 12)),
            layout: PenLayoutDirection.none,
            children: [chip]
        )))
        let pixels = try Self.render([card], [
            "card": PenRect(x: 20, y: 20, width: 60, height: 60),
            "chip": PenRect(x: 0, y: 0, width: 20, height: 20),
        ])
        let corner = pixels.pixel(22, 22)
        #expect(corner == PixelGrid.RGBA(r: 255, g: 136, b: 0, a: 255), "the child is untouched; got \(corner)")
    }

    @Test("Every outer shadow in the array is drawn")
    func everyOuterShadowIsDrawn() throws {
        let card = PenNode(id: "card", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(
            fills: .single(.shorthand("#EEEEEE")),
            effects: .multiple([
                Self.shadow(.outer, "#FF0000FF", x: -20, y: 0, blur: 0),
                Self.shadow(.outer, "#0000FFFF", x: 20, y: 0, blur: 0),
                Self.shadow(.outer, "#00FF00FF", x: 0, y: 20, blur: 0),
            ])
        )))
        let pixels = try Self.render([card], ["card": PenRect(x: 35, y: 35, width: 30, height: 30)])
        #expect(pixels.pixel(25, 50) == PixelGrid.RGBA(r: 255, g: 0, b: 0, a: 255), "left: \(pixels.pixel(25, 50))")
        #expect(pixels.pixel(75, 50) == PixelGrid.RGBA(r: 0, g: 0, b: 255, a: 255), "right: \(pixels.pixel(75, 50))")
        #expect(pixels.pixel(50, 75) == PixelGrid.RGBA(r: 0, g: 255, b: 0, a: 255), "below: \(pixels.pixel(50, 75))")
    }

    @Test("An outer shadow does not show through a translucent fill")
    func outerShadowIsKnockedOut() throws {
        let card = PenNode(id: "card", common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(
            fills: .single(.shorthand("#FF000040")),
            effects: .single(Self.shadow(.outer, "#000000FF", x: 10, y: 10, blur: 0))
        )))
        let paper = PenNode(
            id: "paper", common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FFFFFF"))))
        )
        let pixels = try Self.render([paper, card], [
            "paper": PenRect(x: 0, y: 0, width: 100, height: 100),
            "card": PenRect(x: 30, y: 30, width: 40, height: 40),
        ])
        let inside = pixels.pixel(60, 60)
        #expect(inside.r == 255 && inside.g > 185, "the fill shows over white, not the shadow; got \(inside)")
        let outside = pixels.pixel(75, 75)
        #expect(outside == PixelGrid.RGBA(r: 0, g: 0, b: 0, a: 255), "the shadow is full strength; got \(outside)")
    }

    @Test("A frame casts the shadow of its box, not of its children")
    func frameCastsItsBox() throws {
        let chip = PenNode(
            id: "chip", common: PenNodeCommon(),
            kind: .rectangle(PenNode.RectangleData(fills: .single(.shorthand("#FF8800"))))
        )
        let holder = PenNode(id: "holder", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(
            effects: .single(Self.shadow(.outer, "#000000FF", x: 10, y: 10, blur: 0)),
            layout: PenLayoutDirection.none,
            children: [chip]
        )))
        let pixels = try Self.render([holder], [
            "holder": PenRect(x: 20, y: 20, width: 40, height: 40),
            "chip": PenRect(x: 30, y: 30, width: 30, height: 30),
        ])
        #expect(pixels.pixel(35, 65).a == 255 && pixels.pixel(35, 65).r == 0, "box shadow: \(pixels.pixel(35, 65))")
        #expect(pixels.pixel(85, 85).a == 0, "the child casts nothing: \(pixels.pixel(85, 85))")
    }
}
