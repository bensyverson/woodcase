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
    /// Porter–Duff plus, so it sums alphas over a translucent one). Standard CSS has no
    /// linear burn, which takes `color-burn`, the nearest; ``svgStyle`` follows it with
    /// WebKit's exact `plus-darker`. `light` is CSS's `lighten`. An unknown mode blends
    /// normally.
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

    /// A `mix-blend-mode` keyword that only some browsers know, written after
    /// ``cssMixBlendMode`` so that a browser that knows it draws it and one that does not
    /// drops the declaration and keeps the first; `nil` when there is none.
    ///
    /// Linear burn's is `plus-darker`, which WebKit draws as an exact linear burn and Chrome
    /// does not know (Ben's ruling, 2026-10-21). It is a Porter–Duff plus, like
    /// `plus-lighter`, so over a translucent backdrop it departs from the renderer.
    var cssMixBlendModeRefinement: String? {
        self == .linearBurn ? "plus-darker" : nil
    }

    /// The `style` attribute that blends an SVG element in this mode, or `nil` for none: one
    /// `mix-blend-mode` declaration, and a second for ``cssMixBlendModeRefinement``.
    var svgStyle: String? {
        guard let keyword = cssMixBlendMode else { return nil }
        return ([keyword] + [cssMixBlendModeRefinement].compactMap(\.self))
            .map { "mix-blend-mode:" + $0 }
            .joined(separator: ";")
    }
}
