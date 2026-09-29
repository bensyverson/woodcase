//
//  SwiftUIPaintLayer.swift
//  Woodcase
//

/// One enabled fill as SwiftUI: its paint, and the fill's own opacity and blend mode.
///
/// A paint is a `ShapeStyle` where SwiftUI has one (a color, one of its gradients), and a
/// view where it does not (an image placed by its mode, the support file's `PenGradient`).
/// A stack of styles keeps SwiftUI's idiom, `.fill(top)` over `.background(lower, in:)`;
/// one view in the stack makes every layer a view (``view``), in a `ZStack` clipped to
/// the node.
struct SwiftUIPaintLayer: Friendly {
    /// How the paint is written.
    enum Content: Friendly {
        /// A `ShapeStyle` expression: `Color(hex: 0xFF0000)`, `.linearGradient(…)`.
        case style(String)

        /// A view that fills the box it is offered.
        case view(SwiftUIViewCode)
    }

    /// The paint.
    var content: Content

    /// The fill's opacity, when below 1.
    var opacity: Double?

    /// The fill's blend mode as SwiftUI names it (`.multiply`), when not normal.
    var blendMode: String?

    /// Whether the paint is a plain color, which text painted with it alone keeps as
    /// `foregroundStyle`.
    var isColor = false

    /// Whether the layer is an opaque color of normal blend, which nothing under it shows
    /// through.
    var covers = false

    /// Whether the paint is a view drawn past its box when the view is given room with
    /// `penPaintBleed(_:)` — a `PenGradient`, which Pen pads beyond the box; an image is
    /// drawn only where it is placed.
    var extendsPastBox = false

    /// The layer as a `ShapeStyle` expression, its opacity and blend mode applied, or
    /// `nil` when its paint is a view.
    var style: String? {
        guard case let .style(style) = content else { return nil }
        // A prop falling back to the theme (`tint ?? theme.accent`) takes its opacity whole.
        let grouped = style.contains(" ?? ") && (opacity != nil || blendMode != nil)
        var expression = grouped ? "(\(style))" : style
        if let opacity {
            expression += ".opacity(\(SwiftUILiteral.number(opacity)))"
        }
        if let blendMode {
            expression += ".blendMode(\(blendMode))"
        }
        return expression
    }

    /// The layer as a view filling its box: a style fills a `Rectangle`.
    var view: SwiftUIViewCode {
        var view: SwiftUIViewCode = switch content {
        case let .style(style): SwiftUIViewCode(head: "Rectangle()").modified(".fill(\(style))")
        case let .view(view): view
        }
        if let opacity {
            view = view.modified(".opacity(\(SwiftUILiteral.number(opacity)))")
        }
        if let blendMode {
            view = view.modified(".blendMode(\(blendMode))")
        }
        return view
    }
}
