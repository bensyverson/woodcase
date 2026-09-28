//
//  BatchApplier+Placement.swift
//  Woodcase
//

import Foundation

extension BatchApplier {
    /// Where a root-level node's `x` and `y` came from, and so whether the
    /// applier is free to choose them.
    enum RootCoordinates: Friendly {
        /// The author wrote them, in the subtree an `add` carries. They mean what
        /// they say, and the applier leaves them alone.
        case authored

        /// They came along with the node a `cp` copied. They describe where the
        /// *source* sits, so they say nothing about where the copy belongs — only
        /// the properties the caller passed alongside the copy do.
        case copied
    }

    /// Gives a root-level node somewhere empty to be, if it did not say where.
    ///
    /// The document's roots are artboards on an infinite canvas: two at the same
    /// coordinates sit on top of each other, and an agent writing a subtree has
    /// no way to know what is already out there. So a root-level node with no
    /// coordinates of its own is placed ``RootOverlap/margin`` to the right of the
    /// *rightmost* root — the rightmost by settled edge, whatever order the roots are
    /// declared in — aligned with the topmost one. Placing it past every existing edge
    /// is what makes it impossible for the result to intersect anything, and
    /// ``RootOverlap`` is the check that says so.
    ///
    /// What counts as "of its own" is ``RootCoordinates``. An authored node that
    /// declares *either* coordinate is left alone — the author was being specific,
    /// and guessing the other half would fight them. A copied node is placed
    /// whatever it carries, because what it carries is the source's position; a
    /// caller who wants the copy somewhere in particular passes `x`/`y` in the
    /// copy's properties, which are applied after the insert and win outright.
    ///
    /// Nodes added to a laid-out parent are never placed: their parent's layout
    /// positions them, and coordinates would only be ignored.
    ///
    /// Positions come from ``RootOverlap/roots(in:textMeasurer:)`` rather than the declared
    /// `x`/`y`, so a root sized to its content is measured at the width it actually
    /// occupies — and a reusable component definition is measured at all, which the
    /// layout cache's expansion drops.
    ///
    /// - Parameters:
    ///   - node: The subtree about to be inserted at the root.
    ///   - document: The document it is going into.
    ///   - coordinates: Where the node's own coordinates came from.
    /// - Returns: The node, with coordinates if it needed them.
    static func placedAtRoot(
        _ node: PenNode,
        in document: EditableDocument,
        coordinates: RootCoordinates
    ) -> PenNode {
        if coordinates == .authored, node.common.x != nil || node.common.y != nil {
            return node
        }

        let roots = RootOverlap.roots(in: document).map(\.rect)
        guard !roots.isEmpty else { return node }

        var placed = node
        placed.common.x = .literal((roots.map { $0.x + $0.width }.max() ?? 0) + RootOverlap.margin)
        placed.common.y = .literal(roots.map(\.y).min() ?? 0)
        return placed
    }
}
