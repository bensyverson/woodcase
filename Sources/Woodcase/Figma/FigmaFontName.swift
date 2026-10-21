//
//  FigmaFontName.swift
//  Woodcase
//

/// A Figma `FontName`: a family and a style name such as `Bold Italic`.
struct FigmaFontName: Friendly {
    /// What Pen needs of a face: its CSS weight, whether it is italic, and its natural line
    /// height as a multiple of the size, when Figma recorded it.
    struct Face: Friendly {
        /// The CSS weight, 100 to 900.
        var weight: Double
        /// Whether the face is italic or oblique.
        var isItalic: Bool
        /// The font's own line height as a multiple of its size, if known.
        var naturalLineHeight: Double?
    }

    /// The family, e.g. `Inter`.
    var family: String
    /// The style name, e.g. `Semi Bold Italic`.
    var style: String

    /// Reads a `FontName` struct; a missing one is Figma's default, Inter Regular.
    init(_ value: KiwiValue?) {
        family = value?["family"]?.stringValue ?? "Inter"
        style = value?["style"]?.stringValue ?? "Regular"
    }

    /// The face, from the `fontMetaData` Figma derived for this name when the message
    /// carries it, else read from the style name.
    func face(in derivedTextData: KiwiValue?) -> Face {
        for entry in derivedTextData?["fontMetaData"]?.arrayValue ?? [] {
            guard entry["key"]?["family"]?.stringValue == family, entry["key"]?["style"]?.stringValue == style,
                  let weight = entry["fontWeight"]?.doubleValue
            else { continue }
            return Face(
                weight: weight, isItalic: entry["fontStyle"]?.enumName == "ITALIC",
                naturalLineHeight: entry["fontLineHeight"]?.doubleValue
            )
        }
        return Face(weight: Self.weight(ofStyle: style), isItalic: Self.isItalic(style: style))
    }

    /// The CSS weight a style name says: `Thin` 100 through `Black` 900, 400 when it names
    /// none.
    static func weight(ofStyle style: String) -> Double {
        let words = style.lowercased().replacingOccurrences(of: "italic", with: "").replacingOccurrences(of: "oblique", with: "")
        let squashed = words.filter { !$0.isWhitespace && $0 != "-" }
        for (names, weight) in weights where names.contains(where: { squashed == $0 }) {
            return weight
        }
        return 400
    }

    /// Whether a style name says italic or oblique.
    static func isItalic(style: String) -> Bool {
        let lowered = style.lowercased()
        return lowered.contains("italic") || lowered.contains("oblique")
    }

    /// Style names and the weights they say.
    private static let weights: [(names: [String], weight: Double)] = [
        (["thin", "hairline"], 100),
        (["extralight", "ultralight"], 200),
        (["light"], 300),
        (["regular", "normal", "book", ""], 400),
        (["medium"], 500),
        (["semibold", "demibold"], 600),
        (["bold"], 700),
        (["extrabold", "ultrabold"], 800),
        (["black", "heavy"], 900),
    ]
}
