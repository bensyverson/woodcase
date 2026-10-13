//
//  PenFontWeight.swift
//  Woodcase
//

/// The reading of a .pen `fontWeight` string as a CSS weight, 100 to 900.
///
/// It needs nothing but the standard library, so the Core Text renderer
/// (``PenTextMeasurer/mapWeightToAxisValue(_:)``) and the SwiftUI emitter — which must
/// build without Core Text — read a weight the same way.
public enum PenFontWeight {
    /// Every keyword a `fontWeight` may say instead of a number, lightest first, and
    /// synonyms beside each other: `"thin"` through `"heavy"`.
    public static let keywords: [String] = table.map(\.keyword)

    /// The CSS weight a `fontWeight` string names.
    ///
    /// - Parameter weight: A keyword (`"bold"`, `"semibold"`, case-insensitive) or a
    ///   number (`"650"`).
    /// - Returns: The keyword's weight, the number itself, or 400 for anything else.
    public static func cssWeight(_ weight: String) -> Double {
        let keyword = weight.lowercased()
        return table.first { $0.keyword == keyword }?.weight ?? Double(weight) ?? 400
    }

    /// Each keyword and the CSS weight it names.
    private static let table: [(keyword: String, weight: Double)] = [
        ("thin", 100),
        ("extralight", 200), ("ultralight", 200),
        ("light", 300),
        ("normal", 400), ("regular", 400),
        ("medium", 500),
        ("semibold", 600), ("demibold", 600),
        ("bold", 700),
        ("extrabold", 800), ("ultrabold", 800),
        ("black", 900), ("heavy", 900),
    ]
}
