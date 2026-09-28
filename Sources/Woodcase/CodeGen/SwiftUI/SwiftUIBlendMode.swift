//
//  SwiftUIBlendMode.swift
//  Woodcase
//

/// SwiftUI's spelling of a .pen blend mode.
enum SwiftUIBlendMode {
    /// The `BlendMode` case for `mode`, without its dot, or `nil` for a mode this build
    /// does not know.
    ///
    /// Every known mode is exact. `linearBurn` and `linearDodge` are `plusDarker` and
    /// `plusLighter`, the same formulas under Apple's names — which is closer to Pen than
    /// the Core Graphics renderer's `multiply` and `screen`, since CG has neither — and
    /// Pen's `light` is `lighten`.
    static func name(for mode: PenBlendMode) -> String? {
        switch mode {
        case .normal: "normal"
        case .darken: "darken"
        case .multiply: "multiply"
        case .linearBurn: "plusDarker"
        case .colorBurn: "colorBurn"
        case .light: "lighten"
        case .screen: "screen"
        case .linearDodge: "plusLighter"
        case .colorDodge: "colorDodge"
        case .overlay: "overlay"
        case .softLight: "softLight"
        case .hardLight: "hardLight"
        case .difference: "difference"
        case .exclusion: "exclusion"
        case .hue: "hue"
        case .saturation: "saturation"
        case .color: "color"
        case .luminosity: "luminosity"
        case .unknown: nil
        }
    }
}
