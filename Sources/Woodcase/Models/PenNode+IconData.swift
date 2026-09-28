//
//  PenNode+IconData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Icon

    /// Type-specific data for an `icon` node — a single glyph drawn from a bundled
    /// or user-registered icon font.
    ///
    /// See ``PenIconFontRegistry`` for how `library`/`icon` resolve to a codepoint
    /// and font, and `PenIconFontRenderer` for how the glyph is drawn.
    struct IconData: Friendly {
        public init(
            icon: PenValue<String>? = nil,
            library: PenValue<String>? = nil,
            weight: PenValue<Double>? = nil,
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            fills: PenFills? = nil,
            effects: PenEffects? = nil,
            blendMode: PenBlendMode? = nil
        ) {
            self.icon = icon
            self.library = library
            self.weight = weight
            self.width = width
            self.height = height
            self.fills = fills
            self.effects = effects
            self.blendMode = blendMode
        }

        /// The icon name within `library` (e.g. `"bell"`, `"vpn_lock"`).
        public var icon: PenValue<String>?
        /// The icon font family name (e.g. `"lucide"`, `"Material Symbols Outlined"`).
        public var library: PenValue<String>?
        public var weight: PenValue<Double>?
        public var width: PenSizing?
        public var height: PenSizing?
        public var fills: PenFills?
        public var effects: PenEffects?
        public var blendMode: PenBlendMode?

        public enum CodingKeys: String, CodingKey {
            case icon, library, weight
            case width, height
            case fills = "fill"
            case effects = "effect"
            case blendMode
        }
    }
}
