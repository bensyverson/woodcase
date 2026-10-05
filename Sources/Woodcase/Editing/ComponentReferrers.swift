//
//  ComponentReferrers.swift
//  Woodcase
//

import Foundation

/// Which nodes render each node: the reverse of ``PenNode/renderedComponentIDs``.
///
/// A revision folds in the revision of every node a `ref` renders, and an expansion
/// clones it, so an edit to a component reaches every instance of it — and, through
/// them, every instance of a component that holds one. Walking that reach upwards needs
/// the instances of a node by id, which only a reverse index answers without visiting
/// the whole document; this is that index.
///
/// It is a pure function of the nodes' content, kept exact the way the caches are:
/// ``EditableDocument/invalidatingCaches(touching:_:)`` re-reads each subject after a
/// mutation, and every write to a node's content names that node as a subject. Each
/// node's indexed targets are kept beside the reverse map, so re-reading a node
/// replaces exactly what was indexed for it, whatever it rendered in between.
struct ComponentReferrers: Friendly {
    /// The referrers of each rendered id.
    private var referrers: [String: Set<String>] = [:]

    /// What each indexed node renders; nodes that render nothing are absent.
    private var targets: [String: [String]] = [:]

    /// Indexes every node of a flat store.
    ///
    /// - Parameter nodes: The nodes, by id.
    init(nodes: [String: PenNode]) {
        for (id, node) in nodes {
            reindex(id, rendering: node.renderedComponentIDs)
        }
    }

    /// The nodes that render a node.
    ///
    /// - Parameter target: The rendered node's id.
    /// - Returns: The ids of the nodes that render it, possibly empty.
    func referrers(of target: String) -> Set<String> {
        referrers[target] ?? []
    }

    /// Records what a node renders now, replacing what was indexed for it.
    ///
    /// - Parameters:
    ///   - nodeID: The node.
    ///   - rendered: The ids it renders now; empty for a node that renders nothing or is
    ///     gone.
    /// - Returns: Whether the entry changed.
    @discardableResult
    mutating func reindex(_ nodeID: String, rendering rendered: [String]) -> Bool {
        let old = targets[nodeID] ?? []
        guard old != rendered else { return false }
        for target in old {
            referrers[target]?.remove(nodeID)
            if referrers[target]?.isEmpty == true { referrers[target] = nil }
        }
        for target in rendered {
            referrers[target, default: []].insert(nodeID)
        }
        targets[nodeID] = rendered.isEmpty ? nil : rendered
        return true
    }
}
