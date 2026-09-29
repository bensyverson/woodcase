//
//  PenShadowEffect+CSS.swift
//  Woodcase
//

extension PenEffect.PenShadowEffect {
    /// The color Pen draws a shadow in when it names none: black at half alpha.
    static let defaultCSSColor = "#00000080"

    /// Whether the shadow composites with a blend mode other than normal.
    var isBlended: Bool {
        blendMode.map { $0 != .normal } ?? false
    }

    /// The shadow as one CSS shadow entry, `x y blur color`, without `inset`.
    ///
    /// Pen's `blur` is twice the Gaussian's sigma, which is what a CSS shadow's blur
    /// radius means too, so it passes through unchanged.
    var cssShadow: String {
        css(blurLength: blur?.literalValue ?? 0)
    }

    /// The shadow as one CSS box-shadow entry cast by the box grown by `spread` on every
    /// side, `x y blur spread color`: the band of a stroke reaching past the box casts it
    /// too (``ReactEmitter/shadowSpread(_:)``). Without `inset`.
    func cssShadow(spread: SymbolicLength) -> String {
        guard !spread.isZero else { return cssShadow }
        return css(blurLength: blur?.literalValue ?? 0, spread: spread.css)
    }

    /// The shadow as the argument of a CSS `drop-shadow()`, `x y σ color`.
    ///
    /// A `drop-shadow`'s blur length is the Gaussian's standard deviation, half of Pen's
    /// `blur`: WebKit draws `drop-shadow(8px 10px 12px …)` twice as soft as Pen's `blur: 12`
    /// (`render-group-shadows-group-outer` measured 2.496 against Pen's export with 12px,
    /// 0.482 with 6px; `scripts/png-mae` on a `sleepy shot` of the board's page, 2026-09-27).
    var cssDropShadow: String {
        css(blurLength: (blur?.literalValue ?? 0) / 2)
    }

    /// `x y blur [spread] color`, with the blur length given.
    private func css(blurLength: Double, spread: String? = nil) -> String {
        let x = offset?.x.literalValue ?? 0
        let y = offset?.y.literalValue ?? 0
        let color = color.map(ReactEmitter.cssColorReference) ?? Self.defaultCSSColor
        let lengths = [ReactEmitter.formatPx(x), ReactEmitter.formatPx(y), ReactEmitter.formatPx(blurLength)] + [spread].compactMap(\.self)
        return "\(lengths.joined(separator: " ")) \(color)"
    }
}
