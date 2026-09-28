public extension PenFills {
    /// Whether any of these fills would paint something.
    ///
    /// Pen shows a node's background blur only through a fill that paints: a node with no
    /// fill, or whose every fill is disabled, fully transparent or at opacity 0, shows no
    /// blur, while `#FFFFFF01` is enough (observed in Pen 1.2.14, and the rule Figma uses).
    /// The renderer asks this before blurring a backdrop, and every other renderer should
    /// ask the same question rather than restate it.
    ///
    /// A colour that does not parse — an unresolved `$variable`, say — paints nothing. A
    /// gradient, image, mesh or shader fill paints unless it is disabled or at opacity 0,
    /// whatever its colours; a fill type this build does not know is assumed to paint.
    var hasVisiblePaint: Bool {
        all.contains(where: \.paints)
    }
}

private extension PenFill {
    /// Whether this one fill paints anything; see ``PenFills/hasVisiblePaint``.
    var paints: Bool {
        switch self {
        case let .shorthand(hex):
            Self.isVisible(hex)
        case let .color(fill):
            fill.enabled?.literalValue != false && fill.color.literalValue.map(Self.isVisible) == true
        case let .gradient(fill):
            Self.isShown(enabled: fill.enabled, opacity: fill.opacity)
        case let .image(fill):
            Self.isShown(enabled: fill.enabled, opacity: fill.opacity)
        case let .meshGradient(fill):
            Self.isShown(enabled: fill.enabled, opacity: fill.opacity)
        case let .shader(fill):
            Self.isShown(enabled: fill.enabled, opacity: fill.opacity)
        case .unknown:
            true
        }
    }

    static func isVisible(_ hex: String) -> Bool {
        guard let color = PenColorParser.parse(hex) else { return false }
        return color.alpha > 0
    }

    static func isShown(enabled: PenValue<Bool>?, opacity: PenValue<Double>?) -> Bool {
        enabled?.literalValue != false && opacity?.literalValue != 0
    }
}
