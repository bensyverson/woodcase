//
//  RunLanding.swift
//  Woodcase
//

import Foundation

/// The index rule every multi-node move shares: a run of nodes lands side by side, in
/// the order given, at an index counted among the new parent's children **with the
/// moving nodes taken out** — as a stack reorder counts it, so a run moved forward past
/// its own siblings lands together (leaf 14SEVW).
///
/// ``EditPlanner/planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)`` lands
/// a run in a stored parent one `MoveNode` or `InsertNode` at a time, each taking out
/// only itself; this gives each the index that keeps the run whole: just before the
/// child the run lands in front of — the first child left at or past the index once the
/// run is out — or last. In a slot ``SlotMove`` takes every node out of its fill before
/// any lands, so there the same rule is the index and each next place after it.
struct RunLanding: Friendly {
    /// The new parent's children as the edits so far leave them.
    private var children: [String]

    /// The child the run lands in front of, or `nil` past the last.
    private let follower: String?

    /// Whether the run was given an index; without one each node goes last.
    private let indexed: Bool

    /// The landing of a run at `index` among `children`.
    ///
    /// - Parameters:
    ///   - index: Where the run's first node goes, counted among `children` with
    ///     `moving` taken out; `nil` puts the run last.
    ///   - children: The new parent's children, as they stand.
    ///   - moving: The run's nodes; those among `children` are not counted.
    /// - Throws: ``EditingError/invalidIndex(index:count:)`` for an index past the
    ///   children left once the run is taken out.
    init(index: Int?, among children: [String], moving: Set<String>) throws(EditingError) {
        let staying = children.filter { !moving.contains($0) }
        if let index, !(0 ... staying.count).contains(index) {
            throw EditingError.invalidIndex(index: index, count: staying.count)
        }
        self.children = children
        follower = index.flatMap { $0 < staying.count ? staying[$0] : nil }
        indexed = index != nil
    }

    /// Lands the run's next node: the index its single move or insert takes, or `nil`
    /// to put it last when the run has no index.
    ///
    /// - Parameter id: The node, by the id it has in the new parent after landing.
    mutating func land(_ id: String) -> Int? {
        children.removeAll { $0 == id }
        let index = follower.flatMap { children.firstIndex(of: $0) } ?? children.count
        children.insert(id, at: index)
        return indexed ? index : nil
    }
}
