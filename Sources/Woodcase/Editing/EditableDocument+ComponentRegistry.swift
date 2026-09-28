//
//  EditableDocument+ComponentRegistry.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Populates the component registry by scanning all nodes for `reusable == true`.
    ///
    /// Called during `init` to build the initial registry from the flattened document.
    func populateComponentRegistry() {
        for (nodeID, node) in nodes where node.common.reusable == true {
            componentRegistry[nodeID] = node
        }
    }

    /// Updates the component registry for a single node.
    ///
    /// If the node at the given ID has `reusable == true`, it is added or updated in the
    /// registry. Otherwise, it is removed (if present).
    ///
    /// - Parameter nodeID: The ID of the node to check.
    func updateComponentRegistry(for nodeID: String) {
        if let node = nodes[nodeID], node.common.reusable == true {
            componentRegistry[nodeID] = node
        } else {
            componentRegistry[nodeID] = nil
        }
    }
}
