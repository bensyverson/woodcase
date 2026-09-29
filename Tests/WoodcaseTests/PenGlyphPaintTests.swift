import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Pins which paint a text or icon node's fills give its glyphs: nothing, one solid color
/// Core Text draws them in, or the fills painted through their outlines.
struct PenGlyphPaintTests {
    private static let ramp = PenFill.gradient(PenFill.PenGradientFill(
        gradientType: .linear,
        colors: [
            PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
            PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
        ]
    ))

    private static let disabledRamp = PenFill.gradient(PenFill.PenGradientFill(
        enabled: .literal(false), gradientType: .linear, colors: []
    ))

    private static let red = PenHexColor(red: 255, green: 0, blue: 0)
    private static let black = PenHexColor(red: 0, green: 0, blue: 0)

    /// One fill shape and the paint it gives the glyphs.
    struct Case: CustomTestStringConvertible {
        let label: String
        let fills: PenFills?
        let paint: PenGlyphPaint

        var testDescription: String {
            label
        }
    }

    static let cases: [Case] = [
        Case(label: "no fills", fills: nil, paint: .nothing),
        Case(label: "an empty stack", fills: .multiple([]), paint: .nothing),
        Case(
            label: "only a disabled solid",
            fills: .single(.color(.init(enabled: .literal(false), color: .literal("#FF0000")))),
            paint: .nothing
        ),
        Case(label: "only a disabled gradient", fills: .single(disabledRamp), paint: .nothing),
        Case(label: "an unknown fill type", fills: .single(.unknown(typeName: "future", payload: PenExtras())), paint: .nothing),
        Case(
            label: "one shorthand solid, alpha kept",
            fills: .single(.shorthand("#FF000080")),
            paint: .solid(PenHexColor(red: 255, green: 0, blue: 0, alpha: 128))
        ),
        Case(
            label: "one solid of normal blend",
            fills: .single(.color(.init(blendMode: .normal, color: .literal("#FF0000")))),
            paint: .solid(red)
        ),
        Case(label: "a solid over a disabled gradient", fills: .multiple([disabledRamp, .shorthand("#F00")]), paint: .solid(red)),
        Case(label: "a solid that does not parse draws black", fills: .single(.shorthand("#zzzzzz")), paint: .solid(black)),
        Case(
            label: "an unresolved variable draws black",
            fills: .single(.color(.init(color: .literal("$ink")))),
            paint: .solid(black)
        ),
        Case(label: "a gradient", fills: .single(ramp), paint: .glyphOutlines),
        Case(label: "an image", fills: .single(.image(.init(url: "a.png"))), paint: .glyphOutlines),
        Case(label: "two solids", fills: .multiple([.shorthand("#FF0000"), .shorthand("#0000FF")]), paint: .glyphOutlines),
        Case(
            label: "a multiplied solid",
            fills: .single(.color(.init(blendMode: .multiply, color: .literal("#FF0000")))),
            paint: .glyphOutlines
        ),
    ]

    @Test("Each fill shape gives the glyphs its paint", arguments: cases)
    func paint(_ probe: Case) {
        #expect(PenGlyphPaint(fills: probe.fills) == probe.paint)
    }

    @Test("A solid's color is the one CG hands Core Text, component for component")
    func solidColorIsCoreTexts() throws {
        let paint = PenGlyphPaint(fills: .single(.shorthand("#3366CC80")))
        let expected = try #require(PenColorParser.parse("#3366CC80"))
        #expect(paint.coreTextColor == expected)
    }

    @Test("Paint that is not a lone solid hands Core Text opaque black, the color no glyph shows")
    func otherPaintsHandCoreTextBlack() throws {
        let black = try #require(PenColorParser.parse("#000000"))
        #expect(PenGlyphPaint.glyphOutlines.coreTextColor == black)
        #expect(PenGlyphPaint.nothing.coreTextColor == black)
    }

    @Test("The paint round-trips through JSON")
    func codable() throws {
        for probe in Self.cases {
            let data = try JSONEncoder().encode(probe.paint)
            #expect(try JSONDecoder().decode(PenGlyphPaint.self, from: data) == probe.paint, "\(probe.label)")
        }
    }
}
