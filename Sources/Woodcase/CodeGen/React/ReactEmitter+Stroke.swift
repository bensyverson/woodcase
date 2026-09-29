//
//  ReactEmitter+Stroke.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Stroke

    /// The declarations for a uniform stroke that is one plain color: box-shadows. Any
    /// other stroke — a painted one, or one of per-side widths — is drawn by an overlay
    /// element (``strokeOverlayStyles(_:shape:beneathChildren:box:ctx:)``) and emits nothing
    /// here.
    ///
    /// None of them takes layout space or moves a child, as Pen's stroke does neither: an
    /// inner stroke is an inset box-shadow; a centered one an inset box-shadow of half the
    /// width beside a spread one of the other half, so it straddles the edge as Pen's does;
    /// an outer one a spread box-shadow, which is still a band around a 0×0 box, as Pen
    /// draws one (`render-stroke-bands`), where an outline draws nothing.
    static func emitStroke(_ node: any PenStrokable) -> [(String, String)] {
        guard let colorStr = PaintRoute(node.stroke).plainColor.map(cssColorReference) else {
            return []
        }

        switch node.strokeWidth ?? .uniform(.literal(1)) {
        case let .uniform(value):
            let width = SymbolicLength(value)
            switch node.strokeAlignment ?? .center {
            case .inner:
                return [("boxShadow", "\"inset 0 0 0 \(width.css) \(colorStr)\"")]
            case .center:
                let half = width.scaled(by: 0.5).css
                return [("boxShadow", "\"inset 0 0 0 \(half) \(colorStr), 0 0 0 \(half) \(colorStr)\"")]
            case .outer:
                return [("boxShadow", "\"0 0 0 \(width.css) \(colorStr)\"")]
            }

        case .perSide:
            return []
        }
    }

    /// How far a node's outer shadows spread: the reach of its stroke past its box, since
    /// Pen casts them from the shape grown by that band (``PenShadowSilhouette``;
    /// `render-stroke-bands`). Zero for a stroke with nothing to paint, and for per-side
    /// widths, whose band a uniform spread cannot follow.
    static func shadowSpread(_ stroke: (any PenStrokable)?) -> SymbolicLength {
        guard let stroke, PaintRoute(stroke.stroke) != .none else { return .zero }
        let outsets = StrokeRing(stroke).outsets
        return outsets.isUniform ? outsets.top : .zero
    }

    /// A color fill as a bare CSS color (`#FF0000`, `var(--ink)`), or `nil` for any other fill.
    static func emitFillValueRaw(_ fill: PenFill?) -> String? {
        fill?.solidColor.map(cssColorReference)
    }

    /// The `fill` attribute of a shape drawn as SVG: the topmost enabled solid, since Pen
    /// paints the last enabled fill over the others and an SVG `fill` carries one color,
    /// or `none` when no enabled fill is a color — the rule a text's and an icon's color
    /// follow (`glyphColor(_:)`).
    static func svgFillColor(_ fills: PenFills?) -> String {
        fills?.all.last { $0.isEnabled && $0.solidColor != nil }.flatMap(emitFillValueRaw) ?? "none"
    }

    /// A color as a bare CSS color: a literal as written, a variable as its custom property.
    static func cssColorReference(_ color: PenValue<String>) -> String {
        switch color {
        case let .literal(value): value
        case let .variable(name): "var(--\(name))"
        }
    }
}
