//
//  EditableDocument+Inverse.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Captures pre-mutation state and returns the inverse operation(s).
    ///
    /// Call **before** applying the operation. The returned operations, when applied
    /// in order after the forward operation, will undo its effects.
    ///
    /// Most operations return a single-element array. ``EditOperation/detachRef(_:)``
    /// returns two operations (delete expanded subtree + re-insert original ref).
    ///
    /// - Parameter operation: The operation about to be applied.
    /// - Returns: The inverse operation(s) that undo this operation.
    /// - Throws: ``EditingError`` if required nodes/data can't be found.
    func prepareInverse(of operation: EditOperation) throws -> [EditOperation] {
        switch operation {
        case let .moveNode(op):
            try prepareInverseMove(op)
        case let .insertNode(op):
            [prepareInverseInsert(op)]
        case let .deleteNode(op):
            try prepareInverseDelete(op)
        case let .replaceSubtree(op):
            try [prepareInverseReplaceSubtree(op)]
        case let .updateCommon(op):
            try [prepareInverseUpdateCommon(op)]
        case let .updateKind(op):
            try [prepareInverseUpdateKind(op)]
        case let .setProperties(op):
            try [prepareInverseSetProperties(op)]
        case let .overrideDescendant(op):
            try [prepareInverseOverrideDescendant(op)]
        case let .overrideRoot(op):
            try [prepareInverseOverrideRoot(op)]
        case let .detachRef(op):
            try prepareInverseDetachRef(op)
        case let .addVariable(op):
            [prepareInverseAddVariable(op)]
        case let .updateVariable(op):
            try [prepareInverseUpdateVariable(op)]
        case let .removeVariable(op):
            try [prepareInverseRemoveVariable(op)]
        case let .addImport(op):
            [prepareInverseAddImport(op)]
        case let .updateImport(op):
            try [prepareInverseUpdateImport(op)]
        case let .removeImport(op):
            try [prepareInverseRemoveImport(op)]
        case let .addThemeAxis(op):
            [prepareInverseAddThemeAxis(op)]
        case let .updateThemeAxis(op):
            try [prepareInverseUpdateThemeAxis(op)]
        case let .removeThemeAxis(op):
            try [prepareInverseRemoveThemeAxis(op)]
        }
    }
}

// MARK: - Structural Inverses

extension EditableDocument {
    /// Inverse of move: move back to old parent at old index.
    private func prepareInverseMove(_ op: EditOperation.MoveNode) throws -> [EditOperation] {
        guard nodes[op.nodeID] != nil else {
            throw EditingError.nodeNotFound(id: op.nodeID)
        }
        let oldParentID = parents[op.nodeID]
        let oldIndex: Int? = if let oldParentID {
            children[oldParentID]?.firstIndex(of: op.nodeID)
        } else {
            rootOrder.firstIndex(of: op.nodeID)
        }
        return [.moveNode(EditOperation.MoveNode(
            nodeID: op.nodeID,
            newParentID: oldParentID,
            index: oldIndex
        ))]
    }

    /// Inverse of insert: delete the inserted node.
    private func prepareInverseInsert(_ op: EditOperation.InsertNode) -> EditOperation {
        .deleteNode(EditOperation.DeleteNode(nodeID: op.node.id))
    }

    /// Inverse of delete: re-insert the full subtree at its current position.
    ///
    /// A delete that detaches instances first is three steps forward — detach each
    /// instance, then delete — so its inverse is those steps undone in reverse. Only
    /// the re-inserts can be captured now: the expanded roots the detaches will
    /// produce do not exist yet, so this returns a partial that
    /// ``completeDetachingDeleteInverse(detached:partialInverse:)`` finishes, exactly
    /// as ``completeDetachInverse(expandedRootID:partialInverse:)`` finishes a detach.
    ///
    /// - Returns: The insert that restores the deleted subtree, followed by one insert
    ///   per instance the delete will detach.
    private func prepareInverseDelete(_ op: EditOperation.DeleteNode) throws -> [EditOperation] {
        let subtree = try materializeSubtree(rootID: op.nodeID)
        let parentID = parents[op.nodeID]
        let index: Int? = if let parentID {
            children[parentID]?.firstIndex(of: op.nodeID)
        } else {
            rootOrder.firstIndex(of: op.nodeID)
        }
        var inverse: [EditOperation] = [.insertNode(EditOperation.InsertNode(
            node: subtree,
            parentID: parentID,
            index: index
        ))]

        guard op.instances == .detach else { return inverse }
        for instanceID in try instancesToDetach(for: op) {
            try inverse.append(contentsOf: prepareInverseDetachRef(
                EditOperation.DetachRef(refNodeID: instanceID)
            ))
        }
        return inverse
    }

    /// Inverse of a replace: replace it right back with the subtree it had.
    ///
    /// A replace is its own inverse's shape, which is what makes "rebuild it" undoable
    /// in one step: the node never left its place, so the undo has no position to
    /// reconstruct and restores the subtree exactly as the document held it.
    private func prepareInverseReplaceSubtree(_ op: EditOperation.ReplaceSubtree) throws -> EditOperation {
        try .replaceSubtree(EditOperation.ReplaceSubtree(node: materializeSubtree(rootID: op.node.id)))
    }
}

// MARK: - Property Inverses

extension EditableDocument {
    /// Inverse of updateCommon: restore old common properties.
    private func prepareInverseUpdateCommon(_ op: EditOperation.UpdateCommon) throws -> EditOperation {
        guard let node = nodes[op.nodeID] else {
            throw EditingError.nodeNotFound(id: op.nodeID)
        }
        return .updateCommon(EditOperation.UpdateCommon(
            nodeID: op.nodeID,
            common: node.common
        ))
    }

    /// Inverse of updateKind: restore old kind data.
    private func prepareInverseUpdateKind(_ op: EditOperation.UpdateKind) throws -> EditOperation {
        guard let node = nodes[op.nodeID] else {
            throw EditingError.nodeNotFound(id: op.nodeID)
        }
        return .updateKind(EditOperation.UpdateKind(
            nodeID: op.nodeID,
            kind: node.kind
        ))
    }

    /// Inverse of setProperties: write back the prior value of each key it names.
    ///
    /// An unknown key throws here rather than at apply time, so an undo stack is
    /// never handed an inverse that cannot be replayed.
    private func prepareInverseSetProperties(_ op: EditOperation.SetProperties) throws -> EditOperation {
        guard let node = nodes[op.nodeID] else {
            throw EditingError.nodeNotFound(id: op.nodeID)
        }
        var priorValues: [String: AnyCodable] = [:]
        for path in op.properties.keys {
            priorValues[path] = try NodePropertyCodec.value(at: path, of: node)
        }
        return .setProperties(EditOperation.SetProperties(
            nodeID: op.nodeID,
            properties: priorValues
        ))
    }
}

// MARK: - Component Inverses

extension EditableDocument {
    /// Inverse of overrideDescendant: restore the entry exactly as it stood.
    ///
    /// Restoring the old values is only half of it: a write that *added* a key leaves
    /// one the old map never had, so the inverse unsets whatever the operation brought
    /// in. Without that, undoing `override fontSize=18` on a descendant that had no
    /// `fontSize` left the 18 behind.
    private func prepareInverseOverrideDescendant(_ op: EditOperation.OverrideDescendant) throws -> EditOperation {
        guard let node = nodes[op.refNodeID] else {
            throw EditingError.nodeNotFound(id: op.refNodeID)
        }
        guard case let .ref(refData) = node.kind else {
            throw EditingError.notARefNode(id: op.refNodeID)
        }

        let oldProperties = refData.descendants?[op.descendantID]?.properties ?? [:]
        return .overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: op.refNodeID,
            descendantID: op.descendantID,
            properties: oldProperties,
            unset: Self.keysAdded(by: op.properties, to: oldProperties)
        ))
    }

    /// Inverse of overrideRoot: restore the ref's root overrides exactly as they stood.
    private func prepareInverseOverrideRoot(_ op: EditOperation.OverrideRoot) throws -> EditOperation {
        guard let node = nodes[op.refNodeID] else {
            throw EditingError.nodeNotFound(id: op.refNodeID)
        }
        guard case let .ref(refData) = node.kind else {
            throw EditingError.notARefNode(id: op.refNodeID)
        }

        let oldProperties = refData.rootOverrides ?? [:]
        return .overrideRoot(EditOperation.OverrideRoot(
            refNodeID: op.refNodeID,
            properties: oldProperties,
            unset: Self.keysAdded(by: op.properties, to: oldProperties)
        ))
    }

    /// The keys a write would introduce that the map does not already carry.
    ///
    /// - Parameters:
    ///   - properties: The keys the write assigns.
    ///   - existing: The map as it stands.
    /// - Returns: The keys an inverse has to remove, sorted so the operation compares
    ///   equal to itself however the dictionary happened to be ordered.
    private static func keysAdded(
        by properties: [String: AnyCodable],
        to existing: [String: AnyCodable]
    ) -> [String] {
        properties.keys.filter { existing[$0] == nil }.sorted()
    }

    /// Captures pre-detach state for undo. Returns only the insert-ref operation.
    ///
    /// Since ``EditOperation/detachRef(_:)`` generates random IDs for expanded nodes,
    /// the delete operation for the expanded subtree cannot be determined before the
    /// detach runs. Call ``completeDetachInverse(expandedRootID:partialInverse:)``
    /// after applying the detach to get the full 2-element inverse.
    ///
    /// - Returns: A single-element array containing the insert-ref operation.
    private func prepareInverseDetachRef(_ op: EditOperation.DetachRef) throws -> [EditOperation] {
        guard let node = nodes[op.refNodeID] else {
            throw EditingError.nodeNotFound(id: op.refNodeID)
        }
        guard case .ref = node.kind else {
            throw EditingError.notARefNode(id: op.refNodeID)
        }

        let parentID = parents[op.refNodeID]
        let index: Int? = if let parentID {
            children[parentID]?.firstIndex(of: op.refNodeID)
        } else {
            rootOrder.firstIndex(of: op.refNodeID)
        }

        return [
            .insertNode(EditOperation.InsertNode(node: node, parentID: parentID, index: index)),
        ]
    }

    /// Completes a detach inverse by prepending a delete operation for the expanded root.
    ///
    /// Call after applying ``EditOperation/detachRef(_:)`` to combine the expanded root ID
    /// (from ``DetachResult``) with the partial inverse from ``prepareInverse(of:)``.
    ///
    /// - Parameters:
    ///   - expandedRootID: The root node ID from the detach result.
    ///   - partialInverse: The partial inverse from ``prepareInverse(of:)``.
    /// - Returns: A 2-element array: `[deleteNode(expanded), insertNode(ref)]`.
    public func completeDetachInverse(
        expandedRootID: String,
        partialInverse: [EditOperation]
    ) -> [EditOperation] {
        [.deleteNode(EditOperation.DeleteNode(nodeID: expandedRootID))] + partialInverse
    }

    /// Completes a detaching delete's inverse with the roots its detaches produced.
    ///
    /// Call after ``deleteNode(_:)`` with the results it returned and the partial
    /// inverse from ``prepareInverse(of:)``. The completed list restores the deleted
    /// subtree first — so the component is back before anything points at it again —
    /// then removes each expanded subtree and re-inserts the instance it replaced.
    ///
    /// - Parameters:
    ///   - detached: The results from ``deleteNode(_:)``.
    ///   - partialInverse: The partial inverse from ``prepareInverse(of:)``.
    /// - Returns: The full inverse, to apply in order.
    public func completeDetachingDeleteInverse(
        detached: [DetachResult],
        partialInverse: [EditOperation]
    ) -> [EditOperation] {
        guard let restoreDeleted = partialInverse.first, !detached.isEmpty else {
            return partialInverse
        }
        let removals: [EditOperation] = detached.map {
            .deleteNode(EditOperation.DeleteNode(nodeID: $0.rootNodeID))
        }
        return [restoreDeleted] + removals + partialInverse.dropFirst()
    }
}

// MARK: - Variable Inverses

extension EditableDocument {
    private func prepareInverseAddVariable(_ op: EditOperation.AddVariable) -> EditOperation {
        .removeVariable(EditOperation.RemoveVariable(name: op.name))
    }

    private func prepareInverseUpdateVariable(_ op: EditOperation.UpdateVariable) throws -> EditOperation {
        guard let oldVar = variables?[op.name] else {
            throw EditingError.variableNotFound(name: op.name)
        }
        return .updateVariable(EditOperation.UpdateVariable(name: op.name, variable: oldVar))
    }

    private func prepareInverseRemoveVariable(_ op: EditOperation.RemoveVariable) throws -> EditOperation {
        guard let oldVar = variables?[op.name] else {
            throw EditingError.variableNotFound(name: op.name)
        }
        return .addVariable(EditOperation.AddVariable(name: op.name, variable: oldVar))
    }
}

// MARK: - Import Inverses

extension EditableDocument {
    private func prepareInverseAddImport(_ op: EditOperation.AddImport) -> EditOperation {
        .removeImport(EditOperation.RemoveImport(alias: op.alias))
    }

    private func prepareInverseUpdateImport(_ op: EditOperation.UpdateImport) throws -> EditOperation {
        guard let oldPath = imports?[op.alias] else {
            throw EditingError.importNotFound(alias: op.alias)
        }
        return .updateImport(EditOperation.UpdateImport(alias: op.alias, path: oldPath))
    }

    private func prepareInverseRemoveImport(_ op: EditOperation.RemoveImport) throws -> EditOperation {
        guard let oldPath = imports?[op.alias] else {
            throw EditingError.importNotFound(alias: op.alias)
        }
        return .addImport(EditOperation.AddImport(alias: op.alias, path: oldPath))
    }
}

// MARK: - Theme Inverses

extension EditableDocument {
    private func prepareInverseAddThemeAxis(_ op: EditOperation.AddThemeAxis) -> EditOperation {
        .removeThemeAxis(EditOperation.RemoveThemeAxis(name: op.name))
    }

    private func prepareInverseUpdateThemeAxis(_ op: EditOperation.UpdateThemeAxis) throws -> EditOperation {
        guard let oldOptions = themes?[op.name] else {
            throw EditingError.themeAxisNotFound(name: op.name)
        }
        return .updateThemeAxis(EditOperation.UpdateThemeAxis(name: op.name, options: oldOptions))
    }

    private func prepareInverseRemoveThemeAxis(_ op: EditOperation.RemoveThemeAxis) throws -> EditOperation {
        guard let oldOptions = themes?[op.name] else {
            throw EditingError.themeAxisNotFound(name: op.name)
        }
        return .addThemeAxis(EditOperation.AddThemeAxis(name: op.name, options: oldOptions))
    }
}
