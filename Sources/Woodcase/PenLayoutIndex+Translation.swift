//
//  PenLayoutIndex+Translation.swift
//  Woodcase
//

import Foundation

public extension PenLayoutIndex {
    /// The expanded ids a source invalidation requires laying out again.
    ///
    /// Each source id is read against this expanded tree:
    ///
    /// | Named as | Expanded ids |
    /// |---|---|
    /// | a node (``PenLayoutInvalidation/nodes``) | the node and its ancestors; a `ref` names every node of its instance and their ancestors |
    /// | a subtree (``PenLayoutInvalidation/subtrees``) | every node under it, a ref's instance likewise, and their ancestors |
    /// | a root (``PenLayoutInvalidation/roots``) | every node of the top-level node it expands to — itself, or its instance for a top-level `ref` |
    ///
    /// An id this tree does not hold names nothing: a component definition an export
    /// expansion stripped, a node deleted since. Those edits reach the boards they change
    /// through ``PenLayoutInvalidation/roots``, which the editing document fills with the
    /// roots whose revision they moved.
    ///
    /// A ref names its instance whole because a ref's edit — an override, a new target —
    /// can change any node of the clone, and those nodes have no source id to be named by.
    ///
    /// - Parameter invalidation: What the edits named, by source id.
    /// - Returns: Every expanded node to lay out afresh — the set a measurement cache
    ///   forgets and the dirty set the layout engine reads.
    func expandedIDs(for invalidation: PenLayoutInvalidation) -> Set<String> {
        if invalidation.everything { return Set(entries.keys) }
        var ids: Set<String> = []
        for id in invalidation.nodes {
            if entries[id] != nil {
                insertSpine(of: id, into: &ids)
            }
            for root in instanceRoots(of: id) {
                insertSubtree(of: root, into: &ids)
            }
        }
        for id in invalidation.subtrees {
            insertSubtree(of: id, into: &ids)
            for root in instanceRoots(of: id) {
                insertSubtree(of: root, into: &ids)
            }
        }
        for id in invalidation.roots {
            for root in expandedRoots(of: id) {
                insertSubtree(of: root, into: &ids)
            }
        }
        return ids
    }

    /// The top-level expanded nodes a source root becomes: itself, or the instance a
    /// top-level `ref` placed.
    ///
    /// - Parameter sourceID: The top-level node's source id.
    /// - Returns: Its expanded top-level ids.
    func expandedRoots(of sourceID: String) -> [String] {
        let own = entries[sourceID]?.parent == nil && entries[sourceID] != nil ? [sourceID] : []
        return own + instanceRoots(of: sourceID).filter { entries[$0]?.parent == nil }
    }

    /// Adds a node and its ancestors, stopping at the first ancestor already added.
    private func insertSpine(of id: String, into ids: inout Set<String>) {
        var current: String? = id
        while let next = current, ids.insert(next).inserted {
            current = entries[next]?.parent
        }
    }

    /// Adds every node under a node, and its ancestors.
    private func insertSubtree(of id: String, into ids: inout Set<String>) {
        guard let entry = entries[id] else { return }
        for node in subtree(of: id) {
            ids.insert(node)
        }
        if let parent = entry.parent {
            insertSpine(of: parent, into: &ids)
        }
    }
}
