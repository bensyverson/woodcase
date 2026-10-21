//
//  KiwiValue+FigmaImport.swift
//  Woodcase
//

extension KiwiValue {
    /// Any numeric value as a `Double`: Figma's schema stores most quantities as `float`,
    /// some as `int` or `uint`.
    var doubleValue: Double? {
        switch self {
        case let .float(value): Double(value)
        case let .int(value): Double(value)
        case let .uint(value): Double(value)
        case let .int64(value): Double(value)
        case let .uint64(value): Double(value)
        case let .byte(value): Double(value)
        default: nil
        }
    }
}
