//
//  PenNode+ShadowSpread.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// The node's shadow spreads as its metadata holds them
    /// (``PenMetadata/WoodcaseKey/shadowSpread``), stale or not; empty where it has none or
    /// holds entries ``PenShadowSpread/entries(in:)`` cannot read.
    var shadowSpreads: [PenShadowSpread] {
        guard let value = common.metadata?[woodcase: .shadowSpread] else { return [] }
        return (try? PenShadowSpread.entries(in: value)) ?? []
    }

    /// The spread the shadow at `index` among the node's effects is cast with, or `nil` when
    /// it has none — no entry for it, or one made for another shadow
    /// (``PenShadowSpread/isStale(for:)``).
    ///
    /// Every target that draws a spread reads this, so a stale one is ignored everywhere.
    ///
    /// - Parameter index: The shadow's place among the node's effects, counting from 0.
    /// - Returns: The spread in points, or `nil`.
    func shadowSpread(forEffect index: Int) -> Double? {
        let effects = PenRenderer.effects(for: self)
        guard let entry = shadowSpreads.first(where: { $0.effect == index }), !entry.isStale(for: effects)
        else { return nil }
        return entry.spread
    }

    /// Whether the node holds a spread made for a shadow it no longer has at that place, so
    /// that shadow casts without it.
    var hasStaleShadowSpread: Bool {
        let effects = PenRenderer.effects(for: self)
        return shadowSpreads.contains { $0.isStale(for: effects) }
    }
}
