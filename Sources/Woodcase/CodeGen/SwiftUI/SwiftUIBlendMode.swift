//
//  SwiftUIBlendMode.swift
//  Woodcase
//

/// SwiftUI's spelling of a .pen blend mode.
enum SwiftUIBlendMode {
    /// The `BlendMode` case for `mode`, without its dot, or `nil` for a mode this build
    /// does not know.
    ///
    /// `linearBurn` and `linearDodge` are `plusDarker` and `plusLighter`, the true linear
    /// burn and add where both colors are opaque; being plus operators, they depart from
    /// W3C's formula over a translucent backdrop, which the reference renderer composites
    /// per pixel (``PenBlendLayer``). Pen's `light` is `lighten`.
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
