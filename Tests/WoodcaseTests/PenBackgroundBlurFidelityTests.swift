import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Background-blur behaviors that an MAE against a symmetric backdrop cannot see: which
/// way up the backdrop comes back, which nodes blur at all, and node opacity.
///
/// Each case renders a 100×100 canvas built in code, so a failure names one behavior.
struct PenBackgroundBlurFidelityTests {
    private static let canvas = CGSize(width: 100, height: 100)

    private static func rectangle(_ id: String, fill: PenFills?, effects: PenEffects? = nil) -> PenNode {
        PenNode(id: id, common: PenNodeCommon(), kind: .rectangle(PenNode.RectangleData(fills: fill, effects: effects)))
    }

    private static func blur(_ radius: Double) -> PenEffects {
        .single(.backgroundBlur(PenEffect.PenBackgroundBlurEffect(radius: .literal(radius))))
    }

    /// Red left half, blue right half, and `glass` over the middle 60×60.
    private static func halves(under glass: PenNode) throws -> PixelGrid {
        let doc = PenDocument(version: "2.19", children: [
            rectangle("left", fill: .single(.shorthand("#FF0000"))),
            rectangle("right", fill: .single(.shorthand("#0000FF"))),
            glass,
        ])
        let rects = [
            "left": PenRect(x: 0, y: 0, width: 50, height: 100),
            "right": PenRect(x: 50, y: 0, width: 50, height: 100),
            glass.id: PenRect(x: 20, y: 20, width: 60, height: 60),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: canvas))
        return try #require(PixelGrid(image))
    }

    @Test("The blurred backdrop comes back the right way up")
    func backdropIsNotFlipped() throws {
        // A green band across the top of a red canvas: the only asymmetry is vertical,
        // so a mirrored backdrop puts green at the bottom of the glass instead.
        let doc = PenDocument(version: "2.19", children: [
            Self.rectangle("base", fill: .single(.shorthand("#FF0000"))),
            Self.rectangle("band", fill: .single(.shorthand("#00FF00"))),
            Self.rectangle("glass", fill: .single(.shorthand("#FFFFFF01")), effects: Self.blur(8)),
        ])
        let rects = [
            "base": PenRect(x: 0, y: 0, width: 100, height: 100),
            "band": PenRect(x: 0, y: 0, width: 100, height: 20),
            "glass": PenRect(x: 10, y: 10, width: 80, height: 80),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: Self.canvas))
        let pixels = try #require(PixelGrid(image))

        let top = pixels.pixel(50, 12)
        #expect(top.g > 200 && top.r < 60, "near the band the glass shows green; got \(top)")
        let bottom = pixels.pixel(50, 88)
        #expect(bottom.r > 200 && bottom.g < 60, "far from the band the glass shows red; got \(bottom)")
    }

    @Test("The blurred backdrop comes back the right way up at 2x")
    func backdropIsNotFlippedAtTwoX() throws {
        let doc = PenDocument(version: "2.19", children: [
            Self.rectangle("base", fill: .single(.shorthand("#FF0000"))),
            Self.rectangle("band", fill: .single(.shorthand("#00FF00"))),
            Self.rectangle("glass", fill: .single(.shorthand("#FFFFFF01")), effects: Self.blur(8)),
        ])
        let rects = [
            "base": PenRect(x: 0, y: 0, width: 100, height: 100),
            "band": PenRect(x: 0, y: 0, width: 100, height: 20),
            "glass": PenRect(x: 10, y: 10, width: 80, height: 80),
        ]
        let image = try #require(PenRenderer.render(doc, layoutRects: rects, size: Self.canvas, scale: 2))
        let pixels = try #require(PixelGrid(image))

        #expect(pixels.pixel(100, 24).g > 200, "near the band the glass shows green; got \(pixels.pixel(100, 24))")
        #expect(pixels.pixel(100, 176).g < 60, "far from the band the glass shows red; got \(pixels.pixel(100, 176))")
    }

    @Test("A fully transparent fill shows no blur")
    func transparentFillShowsNoBlur() throws {
        let pixels = try Self.halves(under: Self.rectangle(
            "glass", fill: .single(.shorthand("#FFFFFF00")), effects: Self.blur(20)
        ))
        let edge = pixels.pixel(49, 50)
        #expect(edge == PixelGrid.RGBA(r: 255, g: 0, b: 0, a: 255), "the backdrop stays sharp; got \(edge)")
    }

    @Test("A node with no fill shows no blur")
    func missingFillShowsNoBlur() throws {
        let pixels = try Self.halves(under: Self.rectangle("glass", fill: nil, effects: Self.blur(20)))
        let edge = pixels.pixel(49, 50)
        #expect(edge == PixelGrid.RGBA(r: 255, g: 0, b: 0, a: 255), "the backdrop stays sharp; got \(edge)")
    }

    @Test("A node whose only fill is disabled shows no blur")
    func disabledFillShowsNoBlur() throws {
        let fill = PenFill.color(PenFill.PenColorFill(enabled: .literal(false), color: .literal("#FFFFFF80")))
        let pixels = try Self.halves(under: Self.rectangle("glass", fill: .single(fill), effects: Self.blur(20)))
        let edge = pixels.pixel(49, 50)
        #expect(edge == PixelGrid.RGBA(r: 255, g: 0, b: 0, a: 255), "the backdrop stays sharp; got \(edge)")
    }

    @Test("A barely visible fill is enough to blur")
    func faintFillBlurs() throws {
        let pixels = try Self.halves(under: Self.rectangle(
            "glass", fill: .single(.shorthand("#FFFFFF01")), effects: Self.blur(20)
        ))
        let edge = pixels.pixel(49, 50)
        #expect(edge.b > 60 && edge.r < 200, "the edge is mixed; got \(edge)")
    }

    /// Pen 1.2.14 shows no background blur on a node below opacity 1; Ben ruled that a
    /// Pen bug (2026-09-26), so Woodcase keeps blurring.
    @Test("Background blur still applies below opacity 1")
    func blursBelowFullOpacity() throws {
        var glass = Self.rectangle("glass", fill: .single(.shorthand("#FFFFFF01")), effects: Self.blur(20))
        glass.common.opacity = .literal(0.5)
        let pixels = try Self.halves(under: glass)
        let edge = pixels.pixel(49, 50)
        #expect(edge.b > 40, "the edge is mixed; got \(edge)")
    }
}
