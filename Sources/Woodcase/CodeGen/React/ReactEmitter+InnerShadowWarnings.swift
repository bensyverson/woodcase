//
//  ReactEmitter+InnerShadowWarnings.swift
//  Woodcase
//

extension ReactEmitter {
    /// The warning for a text node whose inner shadows React leaves out: CSS has no inset
    /// text shadow, and Ben ruled against approximating one (2026-09-27).
    static let textInnerShadowWarning = "React draws no inner shadow on text: CSS has no inset text shadow"

    /// The warning for a group whose inner shadows React leaves out: a group is no box, and
    /// CSS has no filter that shadows the inside of what an element paints.
    static let groupInnerShadowWarning = "React draws no inner shadow on a group: CSS has none for painted content"

    /// Warns once for a node whose enabled inner shadows React leaves out — a text or a
    /// group (``innerShadowRoute(_:)``, ``textInnerShadowWarning``, ``groupInnerShadowWarning``).
    static func warnDroppedInnerShadows(_ node: PenNode, ctx: EmitContext) {
        guard case let .dropped(message) = innerShadowRoute(node),
              !NodeEffects(PenRenderer.effects(for: node)).innerShadows.isEmpty
        else { return }
        ctx.warnOnce(message, nodeID: node.id)
    }
}
