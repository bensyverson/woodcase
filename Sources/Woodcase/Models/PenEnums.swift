//
//  PenEnums.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Layout direction for a .pen container node.
public enum PenLayoutDirection: String, Friendly, CaseIterable {
    case none
    case vertical
    case horizontal
}

/// Main-axis distribution of children in a .pen flex container.
public enum PenJustifyContent: String, Friendly, CaseIterable {
    case start
    case center
    case end
    case spaceBetween = "space_between"
    case spaceAround = "space_around"
}

/// Cross-axis alignment of children in a .pen flex container.
public enum PenAlignItems: String, Friendly, CaseIterable {
    case start
    case center
    case end
}

/// Text growth behavior for .pen text nodes.
///
/// Controls how a text box dimensions behave:
/// - `auto`: Box sizes to content, no wrapping.
/// - `fixedWidth`: Width is fixed, height grows to fit wrapped text.
/// - `fixedWidthHeight`: Both dimensions are fixed.
public enum PenTextGrowth: String, Friendly, CaseIterable {
    case auto
    case fixedWidth = "fixed-width"
    case fixedWidthHeight = "fixed-width-height"
}

/// Horizontal text alignment within a .pen text node.
public enum PenTextAlign: String, Friendly, CaseIterable {
    case left
    case center
    case right
    case justify
}

/// Vertical text alignment within a .pen text node.
public enum PenTextAlignVertical: String, Friendly, CaseIterable {
    case top
    case middle
    case bottom
}

/// Stroke alignment relative to the shape boundary — the .pen `strokeAlignment` key.
///
/// The format's own editor omits the key when the stroke is centered, so an absent value means ``center``.
public enum PenStrokeAlign: String, Friendly, CaseIterable {
    /// The stroke paints entirely inside the boundary.
    case inner
    /// The stroke straddles the boundary. The default.
    case center
    /// The stroke paints entirely outside the boundary.
    case outer
}

/// Stroke line join style — the .pen `strokeLinejoin` key.
///
/// The format's own editor omits the key for a mitered join, so an absent value means ``miter``.
public enum PenStrokeJoin: String, Friendly, CaseIterable {
    case miter
    case bevel
    case round
}

/// Stroke line cap style — the .pen `strokeLinecap` key.
///
/// The format's own editor omits the key for a butt cap, so an absent value means ``butt``.
public enum PenStrokeCap: String, Friendly, CaseIterable {
    case butt
    case round
    case square
}

/// SVG path fill rule.
public enum PenFillRule: String, Friendly, CaseIterable {
    case nonzero
    case evenodd
}

/// How a node is positioned within its parent.
public enum PenLayoutPosition: String, Friendly, CaseIterable {
    case auto
    case absolute
}

/// Gradient type for gradient fills.
public enum PenGradientType: String, Friendly, CaseIterable {
    case linear
    case radial
    case angular
}

/// Blend mode for fills and effects.
///
/// Supports all CSS-style blend modes. Unknown modes are preserved
/// via ``unknown(_:)`` for forward compatibility.
public enum PenBlendMode: Hashable, Equatable, Sendable, Codable {
    case normal
    case darken
    case multiply
    case linearBurn
    case colorBurn
    case light
    case screen
    case linearDodge
    case colorDodge
    case overlay
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity
    case unknown(String)

    public var rawString: String {
        switch self {
        case .normal: "normal"
        case .darken: "darken"
        case .multiply: "multiply"
        case .linearBurn: "linearBurn"
        case .colorBurn: "colorBurn"
        case .light: "light"
        case .screen: "screen"
        case .linearDodge: "linearDodge"
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
        case let .unknown(value): value
        }
    }

    public init(rawString: String) {
        switch rawString {
        case "normal": self = .normal
        case "darken": self = .darken
        case "multiply": self = .multiply
        case "linearBurn": self = .linearBurn
        case "colorBurn": self = .colorBurn
        case "light": self = .light
        case "screen": self = .screen
        case "linearDodge": self = .linearDodge
        case "colorDodge": self = .colorDodge
        case "overlay": self = .overlay
        case "softLight": self = .softLight
        case "hardLight": self = .hardLight
        case "difference": self = .difference
        case "exclusion": self = .exclusion
        case "hue": self = .hue
        case "saturation": self = .saturation
        case "color": self = .color
        case "luminosity": self = .luminosity
        default: self = .unknown(rawString)
        }
    }
}

// MARK: - PenBlendMode + Codable

public extension PenBlendMode {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawString: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawString)
    }
}
