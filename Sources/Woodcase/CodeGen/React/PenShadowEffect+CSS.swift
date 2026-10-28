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

    /// The shadow as one outer CSS box-shadow entry cast by the box grown by `spread` on
    /// every side, `x y blur spread color`: the band of a stroke reaching past the box casts
    /// it too (``ReactEmitter/shadowSpread(_:)``). Without `inset`.
    ///
    /// An opaque pure black is written ``webKitSafeBlack``: WebKit fills the solid core of a
    /// blurred outer box-shadow of `#000` that falls outside its box with the element's own
    /// background, and draws `#010101` there, as it does any other color (leaf `S1cB6z`: a
    /// lone red `div` with `box-shadow: 10px 14px 4px #000` showed red where `#010101` showed
    /// black, `peep linesample` of a `sleepy shot`; `0 4px 8px #000`, with no solid core
    /// outside the box, draws right).
    func cssShadow(spread: SymbolicLength) -> String {
        css(blurLength: blur?.literalValue ?? 0, spread: spread.isZero ? nil : spread.css, color: boxShadowColor)
    }

    /// The near-black an opaque pure-black outer box-shadow is written in, one step off
    /// black, which WebKit draws (``cssShadow(spread:)``).
    static let webKitSafeBlack = "#010101"

    /// The shadow's CSS color, with an opaque pure black written ``webKitSafeBlack``.
    private var boxShadowColor: String {
        guard case let .literal(hex)? = color, PenHexColor(hex) == PenHexColor(red: 0, green: 0, blue: 0) else {
            return cssColor
        }
        return Self.webKitSafeBlack
    }

    /// The shadow's CSS color: its own, a variable as its custom property, or Pen's default.
    private var cssColor: String {
        color.map(ReactEmitter.cssColorReference) ?? Self.defaultCSSColor
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

    /// `x y blur [spread] color`, with the blur length given, in the shadow's own color
    /// unless `color` names another.
    private func css(blurLength: Double, spread: String? = nil, color: String? = nil) -> String {
        let x = offset?.x.literalValue ?? 0
        let y = offset?.y.literalValue ?? 0
        let color = color ?? cssColor
        let lengths = [ReactEmitter.formatPx(x), ReactEmitter.formatPx(y), ReactEmitter.formatPx(blurLength)] + [spread].compactMap(\.self)
        return "\(lengths.joined(separator: " ")) \(color)"
    }
}
