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
    /// — the expanded roots it names are the ones ``prepareInverse(of:)`` already
    /// named before the delete ran.
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
            for plan in try detachPlans(deleting: op) {
                try detached.append(detachRef(plan))
            }

            invalidatingLayout(structurallyTouching: allIDs + [parents[op.nodeID]].compactMap(\.self)) {
                // Remove from parent or root. A parent left with no children keeps its
                // declared empty array, so the file says `"children": []` as it would
                // have had it been written that way.
                if let parentID = parents[op.nodeID] {
                    children[parentID]?.removeAll { $0 == op.nodeID }
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
            }

            return detached
        }
    }

    /// Applies an ``EditOperation/DetachRef`` operation.
    ///
    /// Expands the ref node, derives compact IDs for all expanded nodes, removes the
    /// ref, and inserts the expanded subtree at the same position.
    ///
    /// - Parameter op: The detach operation parameters.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    internal func applyDetachRef(_ op: EditOperation.DetachRef) throws {
        _ = try detachRef(op)
    }

    /// Detaches a ref node, returning detailed results.
    ///
    /// Use this overload when you need the ``DetachResult`` (e.g. to construct
    /// undo operations for the expanded subtree). The ids the expansion takes are
    /// derived, not drawn — see ``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)`` — so the
    /// same document detaches to the same ids, and ``prepareInverse(of:)`` can name them
    /// before the detach runs.
    ///
    /// - Parameter op: The detach operation parameters.
    /// - Returns: The ID mapping and new root node ID.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    func detachRef(_ op: EditOperation.DetachRef) throws -> DetachResult {
        guard let plan = try detachPlans(for: [op.refNodeID]).first else {
            throw EditingError.notARefNode(id: op.refNodeID)
        }
        return try detachRef(plan)
    }
}

extension EditableDocument {
    /// Carries out one planned detach.
    ///
    /// - Parameter plan: The detach, from ``detachPlans(for:)``.
    /// - Returns: The ID mapping and new root node ID.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    func detachRef(_ plan: PlannedDetach) throws -> DetachResult {
        try requireRef(plan.refID)

        // The subjects are every node the detach removes and every one it inserts: the
        // inserted expansion can hold instances, which the referrer index has to learn.
        // The ref among them drops the entry the plan's expansion warmed, which the
        // detach has just consumed.
        let subjects = descendantIDs(of: plan.refID) + collectInsertedIDs(in: plan.subtree)
        return try invalidatingCaches(touching: subjects) {
            try detachingRef(plan)
        }
    }

    /// The detach itself, wrapped by ``detachRef(_:)-(PlannedDetach)``'s cache rule.
    ///
    /// - Parameter plan: The detach, from ``detachPlans(for:)``.
    /// - Returns: The ID mapping and new root node ID.
    /// - Throws: Whatever inserting the expansion throws.
    private func detachingRef(_ plan: PlannedDetach) throws -> DetachResult {
        let refID = plan.refID
        let parentID = parents[refID]
        let index: Int? = if let parentID {
            children[parentID]?.firstIndex(of: refID)
        } else {
            rootOrder.firstIndex(of: refID)
        }

        // Delete the ref node (without using applyDelete to avoid the "not found" recursion)
        for id in descendantIDs(of: refID) {
            componentRegistry[id] = nil
            nodes[id] = nil
            children[id] = nil
            parents[id] = nil
        }
        if let parentID {
            children[parentID]?.removeAll { $0 == refID }
        } else {
            rootOrder.removeAll { $0 == refID }
        }

        // Insert the expanded subtree at the same position
        try applyInsert(EditOperation.InsertNode(node: plan.subtree, parentID: parentID, index: index))

        _layoutCache?.invalidateAll()

        return DetachResult(idMapping: plan.idMapping, rootNodeID: plan.subtree.id)
    }
}
