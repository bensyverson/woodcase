//
//  EditableDocument+Queries.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Returns the node with the given ID, or `nil` if not found.
    ///
    /// - Parameter id: The node ID to look up.
    /// - Returns: The stored node (with children stripped), or `nil`.
    func node(id: String) -> PenNode? {
        nodes[id]
    }

    /// Returns the parent ID of the given node, or `nil` if it's a root node.
    ///
    /// - Parameter nodeID: The node to query.
    /// - Returns: The parent node's ID, or `nil` for root nodes.
    func parentID(of nodeID: String) -> String? {
        parents[nodeID]
    }

    /// Returns the ordered child IDs of the given node.
    ///
    /// - Parameter nodeID: The node to query.
    /// - Returns: An ordered array of child IDs, or an empty array if the node
    ///   has no children or doesn't exist.
    func childIDs(of nodeID: String) -> [String] {
        children[nodeID] ?? []
    }

    /// Returns the ancestor chain from the given node up to the root, excluding the node itself.
    ///
    /// The first element is the immediate parent, the last is the root ancestor.
    ///
    /// The walk stops at the first id it has already seen. A settled document has no
    /// cycle in ``parents`` — ``applyLocal(_:)`` refuses a move that would make one —
    /// but ``applyRemote(_:)`` applies a batch one operation at a time, and a batch
    /// whose result is acyclic can pass through a state that is not. This query runs
    /// inside that window (the expansion cache's invalidation rule walks the chain in
    /// a `defer` on every mutation), so it must terminate on a chain that never ends.
    ///
    /// - Parameter nodeID: The node to trace ancestors for.
    /// - Returns: An ordered array of ancestor IDs from nearest to farthest, ending
    ///   before the id that closes a cycle.
    func ancestors(of nodeID: String) -> [String] {
        var result: [String] = []
        var seen: Set<String> = [nodeID]
        var current = nodeID
        while let parent = parents[current], seen.insert(parent).inserted {
            result.append(parent)
            current = parent
        }
        return result
    }

    /// Checks whether a node is a descendant of another node.
    ///
    /// - Parameters:
    ///   - nodeID: The potential descendant.
    ///   - ancestorID: The potential ancestor.
    /// - Returns: `true` if `nodeID` is a transitive child of `ancestorID`. A chain
    ///   that closes on itself without reaching `ancestorID` answers `false` rather
    ///   than walking forever — see ``ancestors(of:)`` for when such a chain exists.
    func isDescendant(_ nodeID: String, of ancestorID: String) -> Bool {
        var seen: Set<String> = [nodeID]
        var current = nodeID
        while let parent = parents[current] {
            if parent == ancestorID { return true }
            guard seen.insert(parent).inserted else { return false }
            current = parent
        }
        return false
    }

    /// All node IDs in the document.
    var allNodeIDs: Set<String> {
        Set(nodes.keys)
    }

    /// The top-level nodes, fully materialized with children reconstructed.
    var rootNodes: [PenNode] {
        rootOrder.compactMap { id in
            try? materializeSubtree(rootID: id)
        }
    }
}
