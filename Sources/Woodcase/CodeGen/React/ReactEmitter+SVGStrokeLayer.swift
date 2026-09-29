//
//  ReactEmitter+SVGStrokeLayer.swift
//  Woodcase
//

extension ReactEmitter {
    /// One layer of a painted SVG stroke, bottom first.
    struct StrokeLayer: Friendly {
        /// How a layer is painted.
        enum Paint: Friendly {
            /// A `stroke` value: a color, or `url(#…)` of a paint server.
            case server(String)
            /// An angular gradient, drawn as a conic layer masked by the stroke.
            case conic(PenFill.PenGradientFill)
        }

        /// How the layer is painted.
        var paint: Paint
        /// Its CSS blend mode against the layers beneath, or `nil` for normal.
        var blend: String?

        /// Whether the layer is a `stroke` attribute on a copy of the shape, which can also
        /// carry the shape's fill.
        var isServer: Bool {
            if case .server = paint { return true }
            return false
        }
    }
}
