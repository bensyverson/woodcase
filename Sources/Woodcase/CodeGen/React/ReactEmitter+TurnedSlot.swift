//
//  ReactEmitter+TurnedSlot.swift
//  Woodcase
//

import Foundation

extension ReactEmitter {
    /// The margin that sizes a turned flow child's flex item to its turned bounds, the
    /// slot Pen's layout gives it (`render-transforms-and-effects`; gotchas, 2026-08-29).
    ///
    /// CSS lays a flex item out at its unturned box whatever its `transform`, so every
    /// later sibling would sit where the unturned box ends. A margin of half the difference
    /// between the turned bounds and the box on each side makes the item's margin box the
    /// bounds, with the box centred in it — where its centre pivot (``TransformPivot/center``)
    /// turns it onto exactly those bounds. A box turned onto its side takes a negative
    /// margin along the side it gave up.
    ///
    /// Only a node the flow places, whose width and height are fixed numbers, gets one: a
    /// size CSS decides is not known here — except a turned `fill_container` child whose
    /// container's numbers fix its box, which ``emitNode(_:component:indent:ctx:isRoot:parentLayout:)``
    /// has already written as fixed (``TurnedFillSizes``). A line keeps its own margins, which
    /// centre its stroke, and gets none.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - width: Its declared width.
    ///   - height: Its declared height.
    ///   - isRoot: Whether it is the component's or page's root, which no flow places.
    ///   - ctx: The emission context, which knows how the node's container places it.
    /// - Returns: A `margin` declaration, or nothing.
    static func turnedSlotStyles(
        _ node: PenNode, width: PenSizing?, height: PenSizing?, isRoot: Bool, ctx: EmitContext
    ) -> [(String, String)] {
        guard !isRoot, ctx.placement(for: node.common) == .flow, let degrees = node.common.rotation?.literalValue,
              let width = width?.fixedValue, let height = height?.fixedValue
        else { return [] }
        let radians = degrees * .pi / 180
        let (cosine, sine) = (abs(cos(radians)), abs(sin(radians)))
        let across = cssNumber((width * cosine + height * sine - width) / 2, decimals: 3)
        let down = cssNumber((width * sine + height * cosine - height) / 2, decimals: 3)
        guard across != "0" || down != "0" else { return [] }
        let length = { (value: String) in value == "0" ? value : "\(value)px" }
        return [("margin", "\"\(length(down)) \(length(across))\"")]
    }
}
