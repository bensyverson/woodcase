import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins what the glyph-outline route keeps: blends, stacks, decorations, color-glyph runs,
/// animation overrides and vector PDF output. Which fills take that route is
/// `PenGlyphPaintTests`'s.
struct PenTextPaintRouteTests {
    private static let ramp = PenFill.gradient(PenFill.PenGradientFill(
        gradientType: .linear,
        rotation: .literal(270),
        colors: [
            PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
            PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
        ]
    ))

    private static let box = PenRect(x: 0, y: 0, width: 240, height: 60)

    @Test("A PDF of gradient text carries a vector shading, not an image")
    func pdfKeepsAShading() throws {
        let node = Self.textNode(fills: .single(Self.ramp))
        let document = PenDocument(version: "2.19", children: [node])
        let data = try PDFExporter.data(pages: [
            PDFExporter.Page(width: 240, height: 60) { context in
                PenRenderer.render(document, layoutRects: [node.id: Self.box], into: context)
            },
        ])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/ShadingType"), "no shading in the PDF")
        #expect(!text.contains("/Subtype /Image"), "the PDF holds an image")
    }

    @Test("An animation override's fills paint a text node")
    func overrideFillsPaintText() throws {
        let node = Self.textNode(fills: .single(.shorthand("#000000")))
        let image = try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: [node]),
            layoutRects: [node.id: Self.box], size: CGSize(width: 240, height: 60),
            overrides: [node.id: NodeOverrides(fills: .single(Self.ramp))]
        ))
        let ink = try Self.opaqueInk(image)
        #expect(ink.contains { $0.b > 128 }, "no blue end of the ramp in \(ink.count) glyph pixels")
    }

    @Test("A single solid with a blend mode blends through the glyphs")
    func blendedSolid() throws {
        let fill = PenFill.color(PenFill.PenColorFill(blendMode: .multiply, color: .literal("#FF0000")))
        let ink = try Self.opaqueInk(Self.renderOnGreen(fills: .single(fill)))
        // Red multiplied over green is black; unblended red would stay red.
        let red = ink.filter { $0.r > 128 }
        #expect(red.isEmpty, "\(red.count) of \(ink.count) glyph pixels are still red")
    }

    @Test("Stacked solids composite through the glyphs one on the other")
    func stackedSolids() throws {
        let fills = PenFills.multiple([.shorthand("#FF0000"), .shorthand("#0000FF80")])
        let ink = try Self.opaqueInk(Self.render(fills: fills))
        // Half blue over red: (127, 0, 128). The top solid alone over nothing would be (0, 0, 128) at alpha 128.
        let blended = ink.filter { abs(Int($0.r) - 127) <= 3 && abs(Int($0.b) - 128) <= 3 }
        #expect(!ink.isEmpty && blended.count == ink.count, "\(blended.count) of \(ink.count) glyph pixels blended")
    }

    @Test("An underline takes the text's paint")
    func underlineTakesThePaint() throws {
        let plain = try #require(PenFillDomainTests.RGBA(Self.render(fills: .single(Self.ramp))))
        let underlined = try #require(PenFillDomainTests.RGBA(Self.render(fills: .single(Self.ramp), underline: true)))
        var underline: [PenFillDomainTests.RGBA.Pixel] = []
        for py in 0 ..< plain.height {
            for px in 0 ..< plain.width where plain.pixel(px, py).a == 0 && underlined.pixel(px, py).a == 255 {
                underline.append(underlined.pixel(px, py))
            }
        }
        #expect(underline.count > 50, "only \(underline.count) underline pixels")
        #expect(underline.contains { $0.b > 128 } && underline.contains { $0.r > 128 }, "the underline is not on the ramp")
    }

    @Test("A color glyph keeps its own colors beside glyphs that take the paint")
    func colorGlyphsKeepTheirColors() throws {
        let ink = try Self.opaqueInk(Self.render(fills: .single(Self.ramp), content: "MM😀"))
        #expect(ink.contains(where: Self.isOnRamp), "the Ms show no ramp")
        // The emoji face is yellow: strong red and green, which the red→blue ramp never has.
        #expect(ink.contains { $0.r > 180 && $0.g > 140 }, "the emoji was not drawn in its own colors")
    }

    // MARK: - Helpers

    private static func textNode(fills: PenFills, content: String = "MMMM", underline: Bool = false) -> PenNode {
        PenNode(
            id: "t",
            common: PenNodeCommon(),
            kind: .text(PenNode.TextData(
                content: .literal(content),
                textGrowth: .fixedWidthHeight,
                fontFamily: .literal("Helvetica"),
                fontSize: .literal(40),
                fontWeight: .literal("700"),
                underline: underline ? .literal(true) : nil,
                fills: fills
            ))
        )
    }

    private static func render(fills: PenFills, content: String = "MMMM", underline: Bool = false) throws -> CGImage {
        let node = textNode(fills: fills, content: content, underline: underline)
        return try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: [node]),
            layoutRects: [node.id: box], size: CGSize(width: 240, height: 60)
        ))
    }

    private static func renderOnGreen(fills: PenFills) throws -> CGImage {
        let text = textNode(fills: fills)
        let frame = PenNode(
            id: "f",
            common: PenNodeCommon(),
            kind: .frame(PenNode.FrameData(fills: .single(.shorthand("#00FF00")), children: [text]))
        )
        return try #require(PenRenderer.render(
            PenDocument(version: "2.19", children: [frame]),
            layoutRects: [frame.id: box, text.id: box], size: CGSize(width: 240, height: 60)
        ))
    }

    /// A pixel of the red→blue ramp off its red end: no green, red and blue summing to 255.
    private static func isOnRamp(_ p: PenFillDomainTests.RGBA.Pixel) -> Bool {
        p.g <= 3 && p.b > 20 && Int(p.r) + Int(p.b) >= 250
    }

    /// Fully opaque pixels that are not the green ground: the glyphs' interiors.
    private static func opaqueInk(_ image: CGImage) throws -> [PenFillDomainTests.RGBA.Pixel] {
        let pixels = try #require(PenFillDomainTests.RGBA(image))
        var ink: [PenFillDomainTests.RGBA.Pixel] = []
        for py in 0 ..< pixels.height {
            for px in 0 ..< pixels.width {
                let p = pixels.pixel(px, py)
                if p.a == 255, !(p.g == 255 && p.r == 0 && p.b == 0) { ink.append(p) }
            }
        }
        return ink
    }
}
