//
//  PlacementSnapping.swift
//  Woodcase
//

import Foundation

/// How far a re-placed node's new `x`/`y` are snapped before they are compared with what
/// the node stores and written (``EditPlanner/planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)``).
public enum PlacementSnapping: String, Friendly {
    /// The coordinates are kept as computed, tidied only of floating-point noise.
    case none

    /// The coordinates are rounded to whole points in the new parent's own space, as a
    /// plain move lands. Rounding comes first, so a stored fractional coordinate the move
    /// would leave in place is written rounded too.
    case wholePoints

    /// The value as this snapping lands it.
    ///
    /// - Parameter value: A coordinate in the new parent's space.
    /// - Returns: `value`, rounded to the nearest whole point for ``wholePoints`` (never
    ///   negative zero).
    func snapped(_ value: Double) -> Double {
        switch self {
        case .none: value
        case .wholePoints: value.rounded() + 0
        }
    }
}
