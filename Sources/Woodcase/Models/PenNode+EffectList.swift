//
//  PenNode+EffectList.swift
//  Woodcase
//

import Foundation

extension PenNode.Kind {
    /// The effects a node of this kind carries, or `nil` for a kind that has none or a node
    /// that writes none.
    ///
    /// The renderer (``PenRenderer/effects(for:)``) and any walk that asks what a node's
    /// effects are — a lint check, a warning about a shader a target drops — read them from
    /// here rather than restating which kinds carry effects.
    var effectList: PenEffects? {
        switch self {
        case let .rectangle(data): data.effects
        case let .ellipse(data): data.effects
        case let .polygon(data): data.effects
        case let .line(data): data.effects
        case let .path(data): data.effects
        case let .frame(data): data.effects
        case let .group(data): data.effects
        case let .text(data): data.effects
        case let .icon(data): data.effects
        case let .browser(data): data.effects
        default: nil
        }
    }
}
