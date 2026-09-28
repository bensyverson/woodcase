//
//  ReactEmitter+Values.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Value Helpers

    static func emitPenValue(_ value: PenValue<Double>) -> String {
        switch value {
        case let .literal(v):
            if v == v.rounded(), !v.isInfinite {
                return String(Int(v))
            }
            return String(v)
        case let .variable(name):
            return "\"var(--\(name))\""
        }
    }

    static func emitPenValue(_ value: PenValue<String>) -> String {
        switch value {
        case let .literal(s): "\"\(s)\""
        case let .variable(name): "\"var(--\(name))\""
        }
    }

    static func emitFontFamily(_ value: PenValue<String>) -> String {
        switch value {
        case let .literal(family): "\"'\(family)'\""
        case let .variable(name): "\"var(--\(name))\""
        }
    }

    static func emitFontWeight(_ value: PenValue<String>) -> String {
        switch value {
        case let .literal(weight):
            if let num = Int(weight) { return String(num) }
            return "\"\(weight)\""
        case let .variable(name): return "\"var(--\(name))\""
        }
    }

    static func emitSizing(_ sizing: PenSizing) -> String? {
        switch sizing {
        case let .fixed(v):
            if v == v.rounded() { return String(Int(v)) }
            return String(v)
        case .fitContent: return "\"fit-content\""
        case .fillContainer: return "\"100%\""
        case let .variable(name): return "\"var(--\(name))\""
        }
    }

    static func emitPenValueRaw(_ value: PenValue<Double>) -> String {
        switch value {
        case let .literal(v):
            if v == v.rounded(), !v.isInfinite { return "\(Int(v))px" }
            return "\(v)px"
        case let .variable(name): return "var(--\(name))"
        }
    }
}
