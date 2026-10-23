//
//  PenNode+ConnectionArrowhead.swift
//  Woodcase
//

import Foundation

public extension PenNode.ConnectionData {
    /// What a connection draws at one of its ends.
    ///
    /// Stored in `metadata.woodcase.startArrowhead` and `metadata.woodcase.endArrowhead`,
    /// written at `kind.startArrowhead` and `kind.endArrowhead`. Absent, or a spelling
    /// Woodcase does not know, is ``none``.
    ///
    /// The set is closed and small on purpose: the three marks diagrams use most — a
    /// filled arrow for direction, an open arrow for a lighter one, a dot for "attached
    /// here" — each drawn in the stroke's own paint and sized from its width, so every
    /// renderer draws them identically from ``Shape`` alone, with no style table to keep
    /// in step.
    enum Arrowhead: String, Friendly, CaseIterable {
        /// Nothing: the line runs to the anchor.
        case none
        /// A filled isosceles triangle whose tip is on the anchor.
        case triangle
        /// An open arrow: two arms stroked like the line, meeting at the anchor.
        case chevron
        /// A filled disc that touches the anchor.
        case circle
    }
}
