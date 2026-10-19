//
//  ScaleAnchor.swift
//  Woodcase
//

import Foundation

/// One of the nine points of a box a scale can hold still: a corner, an edge's midpoint
/// or the center — the anchor grid beside an inspector's Scale field.
public enum ScaleAnchor: String, Friendly, CaseIterable {
    /// The top-left corner.
    case topLeft = "top-left"
    /// The middle of the top edge.
    case top
    /// The top-right corner.
    case topRight = "top-right"
    /// The middle of the left edge.
    case left
    /// The center.
    case center
    /// The middle of the right edge.
    case right
    /// The bottom-left corner.
    case bottomLeft = "bottom-left"
    /// The middle of the bottom edge.
    case bottom
    /// The bottom-right corner.
    case bottomRight = "bottom-right"

    /// The anchor's point on `box`.
    ///
    /// - Parameter box: The box, in any coordinates; the point is in the same ones.
    /// - Returns: The corner, edge midpoint or center the anchor names.
    public func point(in box: PenRect) -> PenPoint {
        PenPoint(x: box.x + box.width * horizontal, y: box.y + box.height * vertical)
    }

    /// How far across the box the anchor is, from 0 at the left edge to 1 at the right.
    private var horizontal: Double {
        switch self {
        case .topLeft, .left, .bottomLeft: 0
        case .top, .center, .bottom: 0.5
        case .topRight, .right, .bottomRight: 1
        }
    }

    /// How far down the box the anchor is, from 0 at the top edge to 1 at the bottom.
    private var vertical: Double {
        switch self {
        case .topLeft, .top, .topRight: 0
        case .left, .center, .right: 0.5
        case .bottomLeft, .bottom, .bottomRight: 1
        }
    }
}
