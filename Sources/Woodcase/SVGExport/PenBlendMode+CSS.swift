//
//  PenBlendMode+CSS.swift
//  Woodcase
//

import Foundation

extension PenBlendMode {
    /// The CSS `mix-blend-mode` keyword an SVG element blends with, or `nil` for `normal`,
    /// which needs none.
    ///
    /// CSS `mix-blend-mode` has no linear burn or linear dodge; they take `color-burn` and
    /// `color-dodge`, as the React emitter does, so the SVG differs from the reference
    /// renderer's true linear burn and add on those two modes. `light` is CSS's `lighten`.
    /// An unknown mode blends normally.
    var cssMixBlendMode: String? {
        switch self {
        case .normal, .unknown: nil
        case .darken: "darken"
        case .multiply: "multiply"
        case .linearBurn, .colorBurn: "color-burn"
        case .light: "lighten"
        case .screen: "screen"
        case .linearDodge, .colorDodge: "color-dodge"
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
