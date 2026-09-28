import Foundation
import Testing
@testable import Woodcase

/// `PenFills.hasVisiblePaint`: the fill gate Pen puts on background blur.
struct PenFillsVisibilityTests {
    private static let gradient = PenFill.PenGradientFill(
        gradientType: .linear,
        colors: [
            PenFill.PenGradientStop(color: .literal("#FF0000"), position: .literal(0)),
            PenFill.PenGradientStop(color: .literal("#0000FF"), position: .literal(1)),
        ]
    )

    @Test("A solid colour with any alpha is visible", arguments: ["#FFFFFF01", "#FFFFFF", "#FFF", "#00000080"])
    func visibleSolid(hex: String) {
        #expect(PenFills.single(.shorthand(hex)).hasVisiblePaint)
    }

    @Test("A fully transparent or unreadable colour is not", arguments: ["#FFFFFF00", "#0000", "$glass", "nonsense"])
    func invisibleSolid(hex: String) {
        #expect(!PenFills.single(.shorthand(hex)).hasVisiblePaint)
    }

    @Test("A disabled or fully transparent colour fill is not visible")
    func colorFill() {
        let disabled = PenFill.color(PenFill.PenColorFill(enabled: .literal(false), color: .literal("#FFFFFF")))
        let clear = PenFill.color(PenFill.PenColorFill(color: .literal("#FFFFFF00")))
        let shown = PenFill.color(PenFill.PenColorFill(color: .literal("#FFFFFF10")))
        #expect(!PenFills.single(disabled).hasVisiblePaint)
        #expect(!PenFills.single(clear).hasVisiblePaint)
        #expect(PenFills.single(shown).hasVisiblePaint)
    }

    @Test("A gradient is visible unless it is disabled or at opacity 0")
    func gradientFill() {
        var hidden = Self.gradient
        hidden.opacity = .literal(0)
        var disabled = Self.gradient
        disabled.enabled = .literal(false)
        #expect(PenFills.single(.gradient(Self.gradient)).hasVisiblePaint)
        #expect(!PenFills.single(.gradient(hidden)).hasVisiblePaint)
        #expect(!PenFills.single(.gradient(disabled)).hasVisiblePaint)
    }

    @Test("A stack is visible when any one of its fills is")
    func stack() {
        #expect(PenFills.multiple([.shorthand("#FFFFFF00"), .shorthand("#FFFFFF01")]).hasVisiblePaint)
        #expect(!PenFills.multiple([.shorthand("#FFFFFF00"), .shorthand("#00000000")]).hasVisiblePaint)
        #expect(!PenFills.multiple([]).hasVisiblePaint)
    }

    @Test("An image fill is visible")
    func imageFill() {
        #expect(PenFills.single(.image(PenFill.PenImageFill(url: "a.png"))).hasVisiblePaint)
    }
}
