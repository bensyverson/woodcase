//
//  PaintRoute.swift
//  Woodcase
//

/// How a text's fills or a node's stroke reach the emitted code.
///
/// A lone solid color keeps the plain declaration its target has for it (React's
/// `color`, a box-shadow, an SVG `stroke` attribute), so plain output does not move.
/// Anything more — a gradient, an image, a mesh, a stack — is painted as layers over the
/// node's box. Disabled fills are gone before the choice is made.
enum PaintRoute: Friendly {
    /// Nothing enabled to paint.
    case none

    /// Exactly one enabled fill, a color — a literal or a document variable — with its
    /// blend mode.
    case solid(color: PenValue<String>, blendMode: PenBlendMode?)

    /// Every enabled fill, bottom to top.
    case painted([PenFill])

    /// The route for `fills`.
    init(_ fills: PenFills?) {
        let enabled = fills?.all.filter(\.isEnabled) ?? []
        if enabled.isEmpty {
            self = .none
        } else if enabled.count == 1, let color = enabled[0].solidColor {
            self = .solid(color: color, blendMode: enabled[0].blendMode)
        } else {
            self = .painted(enabled)
        }
    }

    /// The fills to paint as layers when the route is not a plain color: every fill of
    /// a painted route, or a blended solid (whose blend mode the plain declaration
    /// cannot carry). `nil` for nothing, or for a solid of normal blend.
    var layeredFills: [PenFill]? {
        switch self {
        case .none:
            nil
        case let .solid(color, blendMode):
            blendMode.map { $0 == .normal } ?? true
                ? nil
                : [.color(PenFill.PenColorFill(blendMode: blendMode, color: color))]
        case let .painted(fills):
            fills
        }
    }

    /// The plain color, when the route is a solid of normal blend.
    var plainColor: PenValue<String>? {
        guard case let .solid(color, blendMode) = self, blendMode.map({ $0 == .normal }) ?? true else {
            return nil
        }
        return color
    }
}
