//
//  TransformPivot.swift
//  Woodcase
//

/// Where React's CSS transform turns and flips a node.
///
/// Pen turns and flips a node about its `x`/`y` — the top-left corner of its unturned box —
/// and its layout then places the turned box's bounds. A free-positioned node's `x`/`y` is
/// where React puts its box, so pivoting there draws exactly what Pen draws. Pen grows a
/// flex flow child's slot to its turned bounds with the unturned box centred in it; React
/// grows the flex item by margins to the same bounds (``ReactEmitter/turnedSlotStyles(_:width:height:isRoot:ctx:)``),
/// so turning about the centre lands the box where Pen does.
enum TransformPivot: Friendly {
    /// The node's `x`/`y`, its top-left corner: a node placed by its own coordinates.
    case anchor
    /// The centre of the node's box, CSS's default: a node placed by a flex flow.
    case center

    /// The `transformOrigin` style value this pivot needs, or `nil` for CSS's default.
    var transformOrigin: String? {
        switch self {
        case .anchor: "0 0"
        case .center: nil
        }
    }
}
