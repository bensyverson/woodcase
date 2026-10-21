//
//  ReactEmitter+PaintIsolation.swift
//  Woodcase
//

extension ReactEmitter {
    /// Whether a childless element must isolate so that its paints stay within it.
    ///
    /// A paint blends only with the paints beneath it on its node — fills, then strokes —
    /// and never with what lies behind the node (Ben's reading-1 ruling, 2026-10-20;
    /// `PenPaintStack`). A paint drawn by an element of its own — a stroke overlay, a fill
    /// layer over a crop, an SVG shape copy — blends by `mix-blend-mode`, which reaches as
    /// far as the nearest isolated group, so the node's element must be one. A container
    /// with children that draws such elements isolates already, to keep their negative
    /// `z-index` above its background; isolating one for its paints alone would also stop its
    /// children's own blend modes at it, so only a childless element isolates here, which costs
    /// nothing.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - hasChildren: Whether the node's element holds child elements.
    static func isolatesPaints(_ node: PenNode, hasChildren: Bool) -> Bool {
        !hasChildren && PenPaintStack(node).blends
    }

    /// The warning for a stroke whose lowest paint should blend with the fills beneath it,
    /// which CSS cannot draw.
    static let strokeBlendOverFillsWarning =
        "React blends this node's lowest stroke paint with its other stroke paints but not with its fills, "
            + "which CSS background-blend-mode cannot reach"

    /// Warns once for a box whose stroke overlay stacks several paints, the lowest blended,
    /// over fills: the overlay's layers blend by `background-blend-mode`, which isolates them
    /// from the node's fills, so that paint draws as if it were normal there. A lone stroke
    /// paint blends the overlay itself and is drawn exactly; an SVG shape draws each stroke
    /// paint as an element of its own and is exact too.
    static func warnStrokeBlendOverFills(_ node: PenNode, ctx: EmitContext) {
        switch node.kind {
        case .frame, .rectangle: break
        case let .ellipse(data) where drawsAsBox(data, of: node): break
        default: return
        }
        let stack = PenPaintStack(node)
        let strokes = stack.strokes.filter(\.isEnabled)
        guard strokes.count > 1, !isCroppedImage(strokes[0]), strokes[0].blendMode?.blends == true,
              stack.fills.contains(where: \.isEnabled)
        else { return }
        ctx.warnOnce(strokeBlendOverFillsWarning, nodeID: node.id)
    }

    /// The warning for a linear burn, which CSS has no mode for.
    static let linearBurnWarning = "React draws this node's linear burn as color-burn: CSS has no linear burn"

    /// The warning for a linear dodge in a text's paint stack.
    static let textLinearDodgeWarning =
        "React draws this text's linear dodge paint as color-dodge: background-blend-mode has no add"

    /// Warns once for a node whose blend CSS can only approximate: a linear burn anywhere —
    /// the node's own, a paint's or a shadow's — which takes `color-burn`; and a linear dodge
    /// above another paint in a text's fills, which `background-clip: text` must paint as
    /// background layers, where `plus-lighter` is not allowed, so it takes `color-dodge`.
    /// Everywhere else linear dodge is `mix-blend-mode: plus-lighter`, an exact add over an
    /// opaque backdrop (``mixBlendModeToCSSValue(_:)``).
    static func warnApproximatedBlends(_ node: PenNode, ctx: EmitContext) {
        let stack = PenPaintStack(node)
        let shadows: [PenBlendMode] = PenRenderer.effects(for: node)?.all.compactMap {
            if case let .shadow(shadow) = $0, shadow.enabled?.literalValue != false { return shadow.blendMode }
            return nil
        } ?? []
        let modes = [node.blendMode].compactMap(\.self) + stack.drawn.compactMap(\.paint.blendMode) + shadows
        if modes.contains(.linearBurn) {
            ctx.warnOnce(linearBurnWarning, nodeID: node.id)
        }
        if case .text = node.kind, stack.drawn.dropFirst().contains(where: { $0.paint.blendMode == .linearDodge }) {
            ctx.warnOnce(textLinearDodgeWarning, nodeID: node.id)
        }
    }
}
