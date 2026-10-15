//
//  PenCastShadow.swift
//  Woodcase
//

import CoreGraphics

/// One enabled shadow of a node and the spread it is cast with.
///
/// The spread is the node's ``PenNode/shadowSpread(forEffect:)`` for the shadow's place
/// among its effects — 0 where it has none, or a stale one.
struct PenCastShadow: Friendly {
    /// The shadow.
    let shadow: PenEffect.PenShadowEffect
    /// How far its shape is grown before it is cast, in points; negative shrinks it.
    let spread: CGFloat

    /// A node's enabled shadows, outer and inner, each in array order.
    ///
    /// - Parameter node: The node.
    /// - Returns: The outer shadows and the inner ones.
    static func casts(of node: PenNode) -> (outer: [PenCastShadow], inner: [PenCastShadow]) {
        var outer: [PenCastShadow] = []
        var inner: [PenCastShadow] = []
        for (index, effect) in (PenRenderer.effects(for: node)?.all ?? []).enumerated() {
            guard case let .shadow(shadow) = effect, shadow.enabled?.literalValue != false else { continue }
            let cast = PenCastShadow(shadow: shadow, spread: CGFloat(node.shadowSpread(forEffect: index) ?? 0))
            if shadow.shadowType == .inner {
                inner.append(cast)
            } else {
                outer.append(cast)
            }
        }
        return (outer, inner)
    }
}
