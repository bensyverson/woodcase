//
//  PenBlendMode+CSS.swift
//  Woodcase
//

import Foundation

extension PenBlendMode {
    /// The CSS `mix-blend-mode` keyword an SVG element blends with, or `nil` for `normal`,
    /// which needs none.
    ///
    /// Linear dodge is `plus-lighter`, CSS Compositing Level 2's add, as the React emitter
    /// writes it: the reference renderer's add wherever the backdrop is opaque (it is a
    /// Porter–Duff plus, so it sums alphas over a translucent one). CSS has no linear burn,
    /// which takes `color-burn`, the nearest, so the SVG differs from the reference
    /// renderer there. `light` is CSS's `lighten`. An unknown mode blends normally.
    var cssMixBlendMode: String? {
        switch self {
        case .normal, .unknown: nil
        case .darken: "darken"
        case .multiply: "multiply"
        case .linearBurn, .colorBurn: "color-burn"
        case .light: "lighten"
        case .screen: "screen"
        case .linearDodge: "plus-lighter"
        case .colorDodge: "color-dodge"
        case .overlay: "overlay"
        case .softLight: "soft-light"
        case .hardLight: "hard-light"
        case .difference: "difference"
        case .exclusion: "exclusion"
        case .hue: "hue"
        case .saturation: "saturation"
        case .color: "color"
        case .luminosity: "luminosity"
        }
    }

    /// The `style` attribute that blends an SVG element in this mode, or `nil` for none.
    var svgStyle: String? {
        cssMixBlendMode.map { "mix-blend-mode:" + $0 }
    }
}
