//
//  PenBlendMode+CGBlendMode.swift
//  Woodcase
//

import CoreGraphics

public extension PenBlendMode {
    /// How the reference renderer composites a mode: through Core Graphics, or pixel by
    /// pixel by W3C's formula (``composite(source:over:)``).
    enum Compositing: String, Friendly {
        /// Core Graphics draws the mode by W3C's formula at any alpha, to within 8-bit rounding.
        case coreGraphics
        /// Core Graphics' formula departs from W3C's somewhere, so the renderer reads and
        /// writes the bitmap itself where it can (`PenBlendLayer`).
        case perPixel
    }

    /// How the reference renderer composites this mode.
    ///
    /// Checked on 2026-10-20 by sweeping colors and alphas through a Core Graphics bitmap
    /// against W3C's formula: darken, multiply, lighten, screen, overlay, hard light,
    /// difference and exclusion agree to within a step. Soft light is Core Graphics' own
    /// formula; color dodge and burn ignore a translucent source's alpha in the blend;
    /// plus-darker and plus-lighter are Porter–Duff plus operators, which sum the alphas and
    /// skip the backdrop-alpha term; and the non-separable modes are a few steps off
    /// everywhere. Those composite per pixel.
    var compositing: Compositing {
        switch self {
        case .normal, .darken, .multiply, .light, .screen, .overlay, .hardLight, .difference, .exclusion, .unknown:
            .coreGraphics
        case .linearBurn, .linearDodge, .colorBurn, .colorDodge, .softLight, .hue, .saturation, .color, .luminosity:
            .perPixel
        }
    }

    /// The Core Graphics blend mode nearest this .pen blend mode: exact for the modes that
    /// composite through Core Graphics, and the fallback for the rest where the renderer
    /// cannot reach the pixels (a PDF, or a bitmap format `PenBlendLayer` does not read).
    ///
    /// - `linearBurn` → `.plusDarker` and `linearDodge` → `.plusLighter`: the same results
    ///   where both colors are opaque or the backdrop is transparent, not over a
    ///   translucent backdrop.
    /// - `light` → `.lighten` (naming difference).
    /// - `unknown` → `.normal` (fallback).
    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal: .normal
        case .darken: .darken
        case .multiply: .multiply
        case .linearBurn: .plusDarker
        case .colorBurn: .colorBurn
        case .light: .lighten
        case .screen: .screen
        case .linearDodge: .plusLighter
        case .colorDodge: .colorDodge
        case .overlay: .overlay
        case .softLight: .softLight
        case .hardLight: .hardLight
        case .difference: .difference
        case .exclusion: .exclusion
        case .hue: .hue
        case .saturation: .saturation
        case .color: .color
        case .luminosity: .luminosity
        case .unknown: .normal
        }
    }
}
