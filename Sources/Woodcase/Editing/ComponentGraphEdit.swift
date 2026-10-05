//
//  ComponentGraphEdit.swift
//  Woodcase
//

import Foundation

/// What one operation would change in the parts of a document the component graph is
/// read from — an overlay on the flat store, so the graph after the edit can be read
/// before anything is written.
///
/// Built by ``EditableDocument/componentGraphEdit(for:)`` only for an operation that can
/// add an edge: one that places an instance, a component, or override content naming
/// one. Every other operation can only take edges away, and closes no loop.
struct ComponentGraphEdit: Friendly {
    /// Nodes the edit writes, children stripped; `nil` for a node it removes.
    var nodes: [String: PenNode?] = [:]

    /// Child lists the edit replaces.
    var children: [String: [String]] = [:]

    /// Parents the edit sets; `.some(nil)` for the top level.
    var parents: [String: String?] = [:]

    /// Components a node renders beyond its own payload: the `ref`s an override is about
    /// to write onto it.
    var rendered: [String: [String]] = [:]

    /// The nodes the edit writes at. Every component at or above one of them, after the
    /// edit, may render something it did not before.
    var sites: [String] = []

    /// The overlay of an inserted subtree: every node, stripped, with its child list and
    /// parent.
    ///
    /// - Parameters:
    ///   - root: The subtree, with its inline children.
    ///   - parentID: Where its root goes; `nil` for the top level.
    mutating func insert(_ root: PenNode, under parentID: String?) {
        parents[root.id] = .some(parentID)
        var pending = [root]
        while let node = pending.popLast() {
            nodes[node.id] = .some(PenNode(id: node.id, common: node.common, kind: node.kind.withEmptyChildren(), extras: node.extras))
            let inline = node.kind.inlineChildren
            children[node.id] = inline.map(\.id)
            for child in inline {
                parents[child.id] = .some(node.id)
            }
            sites.append(node.id)
            pending += inline
        }
    }

    /// Whether a subtree holds an instance or a component — anything that can be an end
    /// of an edge.
    ///
    /// - Parameter root: The subtree, with its inline children.
    static func mayAddEdges(_ root: PenNode) -> Bool {
        var pending = [root]
        while let node = pending.popLast() {
            if node.common.reusable == true { return true }
            if case .ref = node.kind { return true }
            pending += node.kind.inlineChildren
        }
        return false
    }
}
