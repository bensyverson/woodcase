//
//  EditableDocument+Detach.swift
//  Woodcase
//

import Foundation

/// Result of a detach operation, providing the ID mapping and new root.
public struct DetachResult: Friendly {
    /// Mapping from old (prefixed) IDs to new compact IDs.
    public var idMapping: [String: String]
    /// The ID of the new root node that replaced the ref.
    public var rootNodeID: String
}

public extension EditableDocument {
    /// Deletes a node and its descendants, detaching any instances it would strand.
    ///
    /// This is what ``apply(_:)`` runs for ``EditOperation/deleteNode(_:)``. Use this
    /// overload when you need the ``DetachResult`` of each instance that was detached
    /// — the expanded roots it names are what
    /// ``completeDetachingDeleteInverse(detached:partialInverse:)`` needs to finish
    /// the undo.
    ///
    /// - Parameter op: The delete operation parameters.
    /// - Returns: One result per instance detached, empty for an ordinary delete.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if the node doesn't exist, or
    ///   ``EditingError/componentHasInstances(componentID:instanceIDs:)`` if the delete
    ///   would strand instances and ``EditOperation/DeleteNode/instances`` is
    ///   ``EditOperation/DeleteNode/Instances/refuse``.
    @discardableResult
    func deleteNode(_ op: EditOperation.DeleteNode) throws -> [DetachResult] {
        try requireNode(op.nodeID)
        let allIDs = descendantIDs(of: op.nodeID)

        // The whole subtree is the subject: it may hold a component definition, or
        // sit inside one. This is a mutating entry point of its own — ``apply(_:)``
        // delegates to it — so it carries the rule itself.
        return try invalidatingCaches(touching: allIDs) {
            var detached: [DetachResult] = []
            for instanceID in try instancesToDetach(for: op) {
                try detached.append(detachRef(EditOperation.DetachRef(refNodeID: instanceID)))
            }

            // Remove from parent or root
            if let parentID = parents[op.nodeID] {
                children[parentID]?.removeAll { $0 == op.nodeID }
                if children[parentID]?.isEmpty == true {
                    children[parentID] = nil
                }
            } else {
                rootOrder.removeAll { $0 == op.nodeID }
            }

            // Remove all nodes and update the registry
            for id in allIDs {
                componentRegistry[id] = nil
                nodes[id] = nil
                children[id] = nil
                parents[id] = nil
            }

            _layoutCache?.invalidateAll()

            return detached
        }
    }

    /// Applies an ``EditOperation/DetachRef`` operation.
    ///
    /// Expands the ref node, generates fresh compact IDs for all expanded nodes,
    /// removes the ref, and inserts the expanded subtree at the same position.
    ///
    /// - Parameter op: The detach operation parameters.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    internal func applyDetachRef(_ op: EditOperation.DetachRef) throws {
        _ = try detachRef(op)
    }

    /// Detaches a ref node, returning detailed results.
    ///
    /// Use this overload when you need the ``DetachResult`` (e.g. to construct
    /// undo operations for the expanded subtree).
    ///
    /// - Parameter op: The detach operation parameters.
    /// - Returns: The ID mapping and new root node ID.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    func detachRef(_ op: EditOperation.DetachRef) throws -> DetachResult {
        try requireRef(op.refNodeID)

        // A ref is always a subject, so this always drops the cache — including the
        // entry `expandRef` warms below, which the detach has just consumed.
        return try invalidatingCaches(touching: [op.refNodeID]) {
            try detachingRef(op)
        }
    }

    /// The detach itself, wrapped by ``detachRef(_:)``'s cache rule.
    ///
    /// - Parameter op: The detach operation parameters.
    /// - Returns: The ID mapping and new root node ID.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    private func detachingRef(_ op: EditOperation.DetachRef) throws -> DetachResult {
        // Expand the ref
        let expanded = try expandRef(nodeID: op.refNodeID)

        // Generate fresh IDs for all nodes in the expanded subtree
        let (remapped, idMapping) = PenID.remapIDs(in: expanded.expandedNode)

        // Record the ref's position
        let parentID = parents[op.refNodeID]
        let index: Int? = if let parentID {
            children[parentID]?.firstIndex(of: op.refNodeID)
        } else {
            rootOrder.firstIndex(of: op.refNodeID)
        }

        // Delete the ref node (without using applyDelete to avoid the "not found" recursion)
        let allRefIDs = descendantIDs(of: op.refNodeID)
        for id in allRefIDs {
            componentRegistry[id] = nil
            nodes[id] = nil
            children[id] = nil
            parents[id] = nil
        }
        if let parentID {
            children[parentID]?.removeAll { $0 == op.refNodeID }
            if children[parentID]?.isEmpty == true {
                children[parentID] = nil
            }
        } else {
            rootOrder.removeAll { $0 == op.refNodeID }
        }

        // Insert the expanded subtree at the same position
        try applyInsert(EditOperation.InsertNode(
            node: remapped,
            parentID: parentID,
            index: index
        ))

        _layoutCache?.invalidateAll()

        return DetachResult(
            idMapping: idMapping,
            rootNodeID: remapped.id
        )
    }
}
