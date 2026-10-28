//
//  PenEffect+Enabled.swift
//  Woodcase
//

import Foundation

extension PenEffect {
    /// Whether the effect is on: only an explicit literal `enabled: false` turns it off.
    ///
    /// Read it on a resolved node, where an `enabled` variable is already a literal. An
    /// ``unknown(typeName:payload:)`` effect is never on, since nothing knows how to draw it.
    var isEnabled: Bool {
        switch self {
        case let .blur(blur): blur.enabled?.literalValue != false
        case let .backgroundBlur(blur): blur.enabled?.literalValue != false
        case let .shadow(shadow): shadow.enabled?.literalValue != false
        case let .shader(shader): shader.enabled?.literalValue != false
        case .unknown: false
        }
    }
}
