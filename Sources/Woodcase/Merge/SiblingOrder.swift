//
//  SiblingOrder.swift
//  Woodcase
//

import Foundation

/// The three-way merge of one child list.
///
/// The members every list holds keep one relative order: theirs' when only the external
/// side reordered them, otherwise ours' — local wins when both did. Every other member
/// goes right after its nearest preceding sibling on its own side, so an insert lands
/// where its writer put it. The local side's members are placed first, so when both
/// sides insert after one sibling, the local insert stays next to it and the external
/// one follows.
enum SiblingOrder {
    /// A merged child list.
    struct Outcome: Friendly {
        /// The merged ids, in order.
        var order: [String]
        /// Whether both sides reordered the shared members differently.
        var bothReordered: Bool
    }

    /// Merges one child list.
    ///
    /// - Parameters:
    ///   - base: The list in the common base.
    ///   - ours: The list on the local side.
    ///   - theirs: The list on the external side.
    ///   - members: The ids that end up under this parent; nothing else is placed.
    /// - Returns: The merged order, and whether both sides reordered it.
    static func merge(base: [String], ours: [String], theirs: [String], members: Set<String>) -> Outcome {
        let inOurs = Set(ours)
        let inTheirs = Set(theirs)
        let inBase = Set(base)
        let shared = members.filter { inOurs.contains($0) && inTheirs.contains($0) && inBase.contains($0) }
        let baseOrder = base.filter(shared.contains)
        let oursOrder = ours.filter(shared.contains)
        let theirsOrder = theirs.filter(shared.contains)
        let oursMoved = oursOrder != baseOrder
        let theirsMoved = theirsOrder != baseOrder

        var placement = Placement(order: theirsMoved && !oursMoved ? theirsOrder : oursOrder)
        placement.place(from: ours, members: members, afterLocal: false)
        placement.place(from: theirs, members: members, afterLocal: true)
        // A member neither list holds has no anchor; it goes last, in a stable order.
        for id in members.subtracting(placement.order).sorted() {
            placement.order.append(id)
        }
        return Outcome(order: placement.order, bothReordered: oursMoved && theirsMoved && oursOrder != theirsOrder)
    }

    /// A list being built, with the ids the local side's pass inserted.
    private struct Placement {
        /// The list so far.
        var order: [String]
        /// The ids the local side's pass inserted, which an external insert steps past.
        var localInserts: Set<String> = []

        /// Places every member of `list` not yet placed after its nearest preceding
        /// sibling in `list`, or first when none precedes it.
        ///
        /// - Parameters:
        ///   - list: One side's child list.
        ///   - members: The ids that may be placed.
        ///   - afterLocal: Whether to step past the local side's inserts at the anchor,
        ///     so the external side's insert follows them.
        mutating func place(from list: [String], members: Set<String>, afterLocal: Bool) {
            var placed = Set(order)
            for (index, id) in list.enumerated() where members.contains(id) && !placed.contains(id) {
                let anchor = list[..<index].last(where: placed.contains)
                var position = anchor.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                if afterLocal {
                    while position < order.count, localInserts.contains(order[position]) {
                        position += 1
                    }
                } else {
                    localInserts.insert(id)
                }
                order.insert(id, at: position)
                placed.insert(id)
            }
        }
    }
}
