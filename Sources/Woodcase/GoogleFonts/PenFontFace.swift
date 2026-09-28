//
//  PenFontFace.swift
//  Woodcase
//

/// One face of a font family a document draws text in: the family, the CSS weight and
/// the style.
///
/// A family is not one file. A static family ships a file per weight and style
/// (`IBMPlexMono-BoldItalic.ttf`); a variable one covers every weight in one file per
/// style (`Lora[wght].ttf`, `Lora-Italic[wght].ttf`). So the unit the font resolver
/// fetches, caches, registers and bundles is the face a text node asks for, and
/// ``GoogleFontMetadata/entry(weight:style:)`` names the file that serves it.
public struct PenFontFace: Friendly, Comparable {
    /// Upright or italic, as Google Fonts' METADATA.pb spells it.
    public enum Style: String, Friendly, CaseIterable {
        /// Upright.
        case normal
        /// Italic.
        case italic
    }

    /// The family name, as a text node's `fontFamily` writes it.
    public var family: String

    /// The CSS weight, 100 to 900 (``PenFontWeight/cssWeight(_:)``).
    public var weight: Int

    /// Upright or italic.
    public var style: Style

    /// A face from its parts.
    public init(family: String, weight: Int, style: Style) {
        self.family = family
        self.weight = weight
        self.style = style
    }

    /// The face a text node sets: its `fontWeight` read as CSS reads it (400 when unset)
    /// and its `fontStyle` (upright unless it says italic).
    ///
    /// - Parameters:
    ///   - family: The node's font family.
    ///   - fontWeight: The node's `fontWeight` string, or `nil`.
    ///   - fontStyle: The node's `fontStyle` string, or `nil`.
    public init(family: String, fontWeight: String?, fontStyle: String?) {
        self.init(
            family: family,
            weight: Int(fontWeight.map(PenFontWeight.cssWeight) ?? 400),
            style: fontStyle?.lowercased() == Style.italic.rawValue ? .italic : .normal
        )
    }

    /// A family's regular face: 400, upright.
    public static func regular(of family: String) -> PenFontFace {
        PenFontFace(family: family, weight: 400, style: .normal)
    }

    /// Orders by family, then weight, then upright before italic.
    public static func < (lhs: PenFontFace, rhs: PenFontFace) -> Bool {
        (lhs.family, lhs.weight, lhs.style == .italic ? 1 : 0) < (rhs.family, rhs.weight, rhs.style == .italic ? 1 : 0)
    }
}
