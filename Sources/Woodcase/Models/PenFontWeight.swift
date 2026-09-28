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
    /// The CSS weight a `fontWeight` string names.
    ///
    /// - Parameter weight: A keyword (`"bold"`, `"semibold"`, case-insensitive) or a
    ///   number (`"650"`).
    /// - Returns: The keyword's weight, the number itself, or 400 for anything else.
    public static func cssWeight(_ weight: String) -> Double {
        switch weight.lowercased() {
        case "thin": 100
        case "extralight", "ultralight": 200
        case "light": 300
        case "normal", "regular": 400
        case "medium": 500
        case "semibold", "demibold": 600
        case "bold": 700
        case "extrabold", "ultrabold": 800
        case "black", "heavy": 900
        default: Double(weight) ?? 400
        }
    }
}
