//
//  PenBlendMode+Blends.swift
//  Woodcase
//

public extension PenBlendMode {
    /// Whether the mode draws otherwise than normal: every mode but ``normal`` and an
    /// ``unknown(_:)`` one, which draws as normal.
    var blends: Bool {
        switch self {
        case .normal, .unknown: false
        default: true
        }
    }
}
