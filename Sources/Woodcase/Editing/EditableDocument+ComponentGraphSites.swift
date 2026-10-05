//
//  EditableDocument+ComponentGraphSites.swift
//  Woodcase
//

import Foundation

/// When an edit can change the component graph, and so the loops memoized with the
/// expansion cache.
extension EditableDocument {
    /// What each subject contributes to the component graph now, or `nil` when no loops
    /// are memoized, so there is nothing to keep.
    ///
    /// - Parameter subjects: The nodes a mutation touches.
    /// - Returns: One site per subject, in order.
    func componentGraphSites(of subjects: [String]) -> [ComponentGraphSite]? {
        guard _expansionCache?.componentLoops != nil else { return nil }
        return subjects.map { nodeID in
            guard let node = nodes[nodeID] else {
                return ComponentGraphSite(parent: nil, isComponent: false, isInsideComponent: false, rendered: [])
            }
            return ComponentGraphSite(
                parent: parents[nodeID],
                isComponent: node.common.reusable == true,
                isInsideComponent: ancestors(of: nodeID).contains { nodes[$0]?.common.reusable == true },
                rendered: node.renderedComponentIDs
            )
        }
    }

    /// Whether an edit can have changed the component graph, judged by its subjects'
    /// sites before and after.
    ///
    /// It can when a subject became or stopped being a component, when one inside a
    /// component (or being one) changed what it renders, or when one moved into, out of
    /// or within a component carrying a component or a rendering node with it. Content
    /// that renders nothing, written inside a component — a nudge, a recolor, a plain
    /// insert — leaves the graph as it was.
    ///
    /// - Parameters:
    ///   - subjects: The nodes the mutation touched.
    ///   - before: Their sites before it.
    ///   - after: Their sites after it.
    /// - Returns: `true` when the memoized loops may no longer stand.
    func invalidatesComponentLoops(_ subjects: [String], before: [ComponentGraphSite], after: [ComponentGraphSite]) -> Bool {
        for (index, nodeID) in subjects.enumerated() {
            let old = before[index], new = after[index]
            let involved = old.isInsideComponent || new.isInsideComponent || old.isComponent || new.isComponent
            if old.isComponent != new.isComponent { return true }
            if old.rendered != new.rendered, involved { return true }
            if old.parent != new.parent, involved, carriesGraphNodes(nodeID) { return true }
        }
        return false
    }

    /// Whether a subtree holds a component or a node that renders one.
    private func carriesGraphNodes(_ rootID: String) -> Bool {
        descendantIDs(of: rootID).contains { id in
            guard let node = nodes[id] else { return false }
            return node.common.reusable == true || !node.renderedComponentIDs.isEmpty
        }
    }
}
