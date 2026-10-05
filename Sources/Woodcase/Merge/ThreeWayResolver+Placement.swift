//
//  ThreeWayResolver+Placement.swift
//  Woodcase
//

import Foundation

/// Where each node sits in the merged tree: its parent, then each child list's order
/// (the design's algorithm steps 3 and 4).
extension ThreeWayResolver {
    /// Resolves the parent of every node the external side moved or inserted.
    ///
    /// A move only theirs made is taken, unless its new parent does not survive — the
    /// node goes back to ours' parent, reported as
    /// ``MergeConflict/Kind/deletedLocallyEditedExternally`` — or ours retyped that
    /// parent to a leaf, or the move would put the node under itself once ours' moves
    /// are in, each of which keeps ours' parent and reports
    /// ``MergeConflict/Kind/bothChanged``. Two different moves keep ours'.
    mutating func resolveParents() {
        var taken: [String] = []
        for id in theirsChanges.nodes.keys.sorted() where ours.nodes[id] != nil && theirs.nodes[id] != nil {
            let oursParent = ours.parents[id]
            let theirsParent = theirs.parents[id]
            guard oursParent != theirsParent else { continue }
            guard base.nodes[id] != nil else {
                reportParent(of: id, .addedTwice)
                continue
            }
            guard theirsChanges.nodes[id]?.keys.contains(.parent) == true else { continue }
            if oursChanges.nodes[id]?.keys.contains(.parent) == true {
                reportParent(of: id, .bothChanged)
            } else if let theirsParent, !survives(theirsParent) {
                reportParent(of: id, .deletedLocallyEditedExternally)
                keepChain(from: id, kind: .editedLocallyDeletedExternally, oursParent: true)
            } else if let theirsParent, !canHoldChildren(theirsParent) {
                reportParent(of: id, .bothChanged)
                keepChain(from: id, kind: .editedLocallyDeletedExternally, oursParent: true)
            } else {
                parentOf[id] = .some(theirsParent)
                taken.append(id)
            }
        }

        for id in contents.keys where ours.nodes[id] == nil {
            parentOf[id] = .some(theirs.parents[id])
        }

        // Declining one move can close a cycle through a move already checked, so check
        // again until none closes. Each pass declines at least one move or ends, and
        // with every external move declined the tree is ours', which has no cycle.
        var declining = true
        while declining {
            declining = false
            for id in taken where parentOf[id] != nil && isUnderItself(id) {
                parentOf.removeValue(forKey: id)
                reportParent(of: id, .bothChanged)
                keepChain(from: id, kind: .editedLocallyDeletedExternally, oursParent: true)
                declining = true
            }
        }
    }

    /// Whether a node's merged parent chain leads back to the node.
    private func isUnderItself(_ id: String) -> Bool {
        var seen: Set<String> = []
        var current = finalParent(of: id)
        while let parent = current {
            if parent == id { return true }
            guard seen.insert(parent).inserted else { return false }
            current = finalParent(of: parent)
        }
        return false
    }

    /// Reports a node whose parent keeps ours' over theirs', with each side's parent.
    private mutating func reportParent(of id: String, _ kind: MergeConflict.Kind) {
        report(
            .parent(nodeID: id), kind, base: base.nodes[id].map { _ in Self.parentValue(base.parents[id]) },
            ours: Self.parentValue(ours.parents[id]), theirs: Self.parentValue(theirs.parents[id])
        )
    }

    /// A parent as a conflict carries it: its id, or ``AnyCodable/null`` for the top level.
    private static func parentValue(_ parent: String?) -> AnyCodable {
        parent.map(AnyCodable.string) ?? .null
    }

    // MARK: - Child lists

    /// Merges every child list a merged change can reach: those theirs changed, those a
    /// node joins or leaves, and the top-level order.
    mutating func resolveChildLists() {
        var lists = Set(theirsChanges.nodes.lazy.filter { _, change in
            change.existence == .added || !change.keys.isDisjoint(with: [.children, .declaredChildren])
        }.map(\.key))
        var topLevel = theirsChanges.document.contains(.rootOrder)
        let leaving = parentOf.keys.compactMap { ours.nodes[$0] == nil ? nil : Optional(ours.parents[$0]) }
            + removed.map { ours.parents[$0] }
        for parent in parentOf.keys.map(finalParent(of:)) + leaving {
            if let parent { lists.insert(parent) } else { topLevel = true }
        }

        for id in lists.sorted() where survives(id) {
            mergeChildren(of: id)
        }
        if topLevel {
            let outcome = mergeOrder(of: nil, base: base.rootOrder, ours: ours.rootOrder, theirs: theirs.rootOrder)
            if outcome != ours.rootOrder { rootOrder = outcome }
        }
    }

    /// Merges one container's child list, keeping the local list's declared-ness unless
    /// only theirs changed it.
    private mutating func mergeChildren(of id: String) {
        let local = ours.nodes[id] != nil
        let oursList = local ? ours.children[id] : nil
        let theirsList = theirs.nodes[id] != nil ? theirs.children[id] : nil
        let baseList = base.children[id]
        let order = mergeOrder(of: id, base: baseList ?? [], ours: oursList ?? [], theirs: theirsList ?? [])

        let declared: Bool = if !local {
            theirsList != nil
        } else if theirs.nodes[id] != nil, (theirsList != nil) != (baseList != nil), (oursList != nil) == (baseList != nil) {
            theirsList != nil
        } else {
            oursList != nil
        }
        let merged: [String]? = order.isEmpty && !declared ? nil : order
        if !local || merged != oursList {
            childLists[id] = .some(merged)
        }
    }

    /// Merges one ordered list of siblings — a container's, or the top level's for a
    /// `nil` parent — over the members the merged tree places there, reporting a
    /// reorder both sides made differently.
    private mutating func mergeOrder(of parent: String?, base: [String], ours: [String], theirs: [String]) -> [String] {
        let members = Set(ours + theirs).filter { survives($0) && finalParent(of: $0) == parent }
        let outcome = SiblingOrder.merge(base: base, ours: ours, theirs: theirs, members: members)
        if outcome.bothReordered {
            let list = { (ids: [String]) in AnyCodable.array(ids.map(AnyCodable.string)) }
            report(.childOrder(parentID: parent), .bothChanged, base: list(base), ours: list(ours), theirs: list(theirs))
        }
        return outcome.order
    }
}
