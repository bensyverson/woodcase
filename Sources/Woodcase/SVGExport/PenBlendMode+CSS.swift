//
//  PenBlendMode+CSS.swift
//  Woodcase
//

import Foundation

extension PenBlendMode {
    /// The CSS `mix-blend-mode` keyword an SVG element blends with, or `nil` for `normal`,
    /// which needs none.
    ///
    /// CSS has no linear burn or linear dodge; they take `color-burn` and `color-dodge`, the
    /// nearest modes, as the React emitter does. CG maps them to multiply and screen instead
    /// (``cgBlendMode``), so the two outputs differ on those two modes. `light` is CSS's
    /// `lighten`. An unknown mode blends normally.
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
