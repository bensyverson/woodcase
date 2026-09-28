//
//  PenBlendMode+CGBlendMode.swift
//  Woodcase
//

import CoreGraphics

public extension PenBlendMode {
    /// The Core Graphics blend mode corresponding to this .pen blend mode.
    ///
    /// Most modes map directly. Approximations:
    /// - `linearBurn` → `.multiply` (no CG equivalent)
    /// - `linearDodge` → `.screen` (no CG equivalent)
    /// - `light` → `.lighten` (naming difference)
    /// - `unknown` → `.normal` (fallback)
    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal: .normal
        case .darken: .darken
        case .multiply: .multiply
        case .linearBurn: .multiply
        case .colorBurn: .colorBurn
        case .light: .lighten
        case .screen: .screen
        case .linearDodge: .screen
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
