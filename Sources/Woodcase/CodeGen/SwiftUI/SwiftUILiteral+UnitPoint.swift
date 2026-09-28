//
//  SwiftUILiteral+UnitPoint.swift
//  Woodcase
//

extension SwiftUILiteral {
    /// A point in the normalised box as a `UnitPoint`: one of SwiftUI's named points
    /// (`.top`, `.bottomTrailing`) where it is one, `UnitPoint(x:y:)` otherwise.
    ///
    /// Coordinates are rounded to nine places, so the sine of a quarter turn writes as
    /// `0.5`, not `0.5000000000000001`; a nanopoint on a thousand-point box is far below
    /// a pixel.
    static func unitPoint(_ point: NormalizedPoint) -> String {
        let x = rounded(point.x)
        let y = rounded(point.y)
        let columns: [Double: String] = [0: "Leading", 0.5: "", 1: "Trailing"]
        let rows: [Double: String] = [0: "top", 0.5: "", 1: "bottom"]
        if let column = columns[x], let row = rows[y] {
            switch (row, column) {
            case ("", ""): return ".center"
            case let ("", column): return ".\(column.prefix(1).lowercased())\(column.dropFirst())"
            default: return ".\(row)\(column)"
            }
        }
        return "UnitPoint(x: \(number(x)), y: \(number(y)))"
    }

    private static func rounded(_ value: Double) -> Double {
        let result = (value * 1e9).rounded() / 1e9
        return result == 0 ? 0 : result
    }
}
