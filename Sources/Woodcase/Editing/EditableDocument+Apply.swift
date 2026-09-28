//
//  EditableDocument+Apply.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Applies an editing operation to the document.
    ///
    /// Every operation checks itself against ``validate(_:)``'s guards before it
    /// writes anything, so a refused operation leaves the document untouched.
    ///
    /// This is the choke point for local editing: every ``EditOperation`` arrives
    /// here, whether the caller used ``apply(_:)`` or ``applyLocal(_:)`` (which
    /// runs the flat store through this method after the CRDT has seen the
    /// operation). So the caches' one invalidation rule wraps the switch
    /// rather than each case — see
    /// ``invalidatingCaches(touching:_:)``.
    ///
    /// - Parameter operation: The operation to apply.
    /// - Throws: ``EditingError`` if the operation fails validation.
    func apply(_ operation: EditOperation) throws {
        try invalidatingCaches(touching: subjects(of: operation)) {
            try applyOperation(operation)
        }
    }
}

extension EditableDocument {
    /// Dispatches one operation to its applier. Call ``apply(_:)`` instead — it is
    /// what keeps the expansion and revision caches in step.
    ///
    /// - Parameter operation: The operation to apply.
    /// - Throws: ``EditingError`` if the operation fails validation.
    private func applyOperation(_ operation: EditOperation) throws {
        switch operation {
        case let .insertNode(op):
            try applyInsert(op)
        case let .deleteNode(op):
            try applyDelete(op)
        case let .moveNode(op):
            try applyMove(op)
        case let .replaceSubtree(op):
            try applyReplaceSubtree(op)
        case let .updateCommon(op):
            try applyUpdateCommon(op)
        case let .updateKind(op):
            try applyUpdateKind(op)
        case let .setProperties(op):
            try applySetProperties(op)
        case let .overrideDescendant(op):
            try applyOverrideDescendant(op)
        case let .overrideRoot(op):
            try applyOverrideRoot(op)
        case let .detachRef(op):
            try applyDetachRef(op)
        case let .addVariable(op):
            try applyAddVariable(op)
        case let .updateVariable(op):
            try applyUpdateVariable(op)
        case let .removeVariable(op):
            try applyRemoveVariable(op)
        case let .addImport(op):
            try applyAddImport(op)
        case let .updateImport(op):
            try applyUpdateImport(op)
        case let .removeImport(op):
            try applyRemoveImport(op)
        case let .addThemeAxis(op):
            try applyAddThemeAxis(op)
        case let .updateThemeAxis(op):
            try applyUpdateThemeAxis(op)
        case let .removeThemeAxis(op):
            try applyRemoveThemeAxis(op)
        }
    }
}

// MARK: - Structural Operations

extension EditableDocument {
    func applyInsert(_ op: EditOperation.InsertNode) throws {
        try validateInsert(op)

        if let parentID = op.parentID {
            var childList = children[parentID] ?? []
            flattenAndInsert(op.node, parentID: parentID)
            if let index = op.index {
                childList.insert(op.node.id, at: index)
            } else {
                childList.append(op.node.id)
            }
            children[parentID] = childList
        } else {
            flattenAndInsert(op.node, parentID: nil)
            if let index = op.index {
                rootOrder.insert(op.node.id, at: index)
            } else {
                rootOrder.append(op.node.id)
            }
        }

        // Update component registry for all inserted nodes
        for nodeID in collectInsertedIDs(in: op.node) {
            updateComponentRegistry(for: nodeID)
        }

        _layoutCache?.invalidateAll()
    }

    /// Applies a delete, discarding the detach results ``deleteNode(_:)`` returns.
    func applyDelete(_ op: EditOperation.DeleteNode) throws {
        _ = try deleteNode(op)
    }

    func applyMove(_ op: EditOperation.MoveNode) throws {
        try validateMove(op)

        // Remove from old location
        if let oldParentID = parents[op.nodeID] {
            children[oldParentID]?.removeAll { $0 == op.nodeID }
            if children[oldParentID]?.isEmpty == true {
                children[oldParentID] = nil
            }
            parents[op.nodeID] = nil
        } else {
            rootOrder.removeAll { $0 == op.nodeID }
        }

        // Insert at new location
        if let newParentID = op.newParentID {
            parents[op.nodeID] = newParentID
            var childList = children[newParentID] ?? []
            childList.insert(op.nodeID, at: op.index ?? childList.count)
            children[newParentID] = childList
        } else {
            rootOrder.insert(op.nodeID, at: op.index ?? rootOrder.count)
        }

        _layoutCache?.invalidateAll()
    }

    // MARK: - Helpers

    /// Writes a subtree into the flat store, keeping the difference between a container
    /// that declares no children and one that declares an empty list — see
    /// ``PenNode/Kind/declaredChildIDs``. That is what lets an `add` and an undo of a
    /// delete round-trip the file's bytes rather than an equivalent tree.
    ///
    /// - Parameters:
    ///   - node: The subtree to write.
    ///   - parentID: The parent to record for its root, or `nil` for a root node.
    private func flattenAndInsert(_ node: PenNode, parentID: String?) {
        let strippedNode = PenNode(
            id: node.id, common: node.common, kind: node.kind.withEmptyChildren(), extras: node.extras
        )
        nodes[node.id] = strippedNode

        if let parentID {
            parents[node.id] = parentID
        }

        if let declared = node.kind.declaredChildIDs {
            children[node.id] = declared
        }
        for child in node.kind.inlineChildren {
            flattenAndInsert(child, parentID: node.id)
        }
    }

    /// Every id an insert of this subtree would add, root first.
    ///
    /// - Parameter node: The subtree about to be, or just, inserted.
    /// - Returns: The subtree's ids in tree order.
    func collectInsertedIDs(in node: PenNode) -> [String] {
        var result = [node.id]
        for child in node.kind.inlineChildren {
            result.append(contentsOf: collectInsertedIDs(in: child))
        }
        return result
    }
}
