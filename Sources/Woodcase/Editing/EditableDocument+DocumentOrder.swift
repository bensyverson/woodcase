//
//  EditableDocument+DocumentOrder.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Every node id, roots first and each subtree depth-first.
    ///
    /// Document order rather than id order, so anything listing nodes — the nodes that
    /// reference a variable, the instances of a component — reads top-down like the
    /// file does, and like ``TreeView``'s rows do. Any node the tree does not reach —
    /// which the flat store should never hold — follows, sorted, so nothing is silently
    /// missed.
    ///
    /// This is the one definition of "document order" over the flat store: a caller
    /// that has a set of ids and wants them in the order a reader would meet them
    /// filters this rather than walking ``rootOrder`` and ``children`` again.
    ///
    /// - Returns: Every id in ``nodes``, in document order.
    /// - Complexity: O(*n*) in the number of nodes.
    func nodeIDsInDocumentOrder() -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func visit(_ nodeID: String) {
            guard seen.insert(nodeID).inserted else { return }
            ordered.append(nodeID)
            for childID in children[nodeID] ?? [] {
                visit(childID)
            }
        }

        for rootID in rootOrder {
            visit(rootID)
        }
        for nodeID in nodes.keys.sorted() where !seen.contains(nodeID) {
            seen.insert(nodeID)
            ordered.append(nodeID)
        }
        return ordered
    }
}
