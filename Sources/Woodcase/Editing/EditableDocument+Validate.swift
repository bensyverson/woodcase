//
//  EditableDocument+Validate.swift
//  Woodcase
//

import Foundation

/// The guards an operation must pass before anything is written.
///
/// Every check ``EditableDocument/apply(_:)`` enforces lives here, once. `apply(_:)`
/// runs the checks for the operation it is about to perform, so a refused edit leaves
/// the document exactly as it was; ``EditableDocument/applyLocal(_:)`` runs the whole
/// pass *first*, before the CRDT is touched, so a refused edit is never replicated to
/// a peer either.
///
/// Nothing in this file mutates the document.
extension EditableDocument {
    /// Checks an operation against every guard ``apply(_:)`` enforces, changing nothing.
    ///
    /// - Parameter operation: The operation to check.
    /// - Throws: The ``EditingError`` ``apply(_:)`` would throw for this operation.
    func validate(_ operation: EditOperation) throws {
        switch operation {
        case let .insertNode(op):
            try validateInsert(op)
        case let .deleteNode(op):
            try validateDelete(op)
        case let .moveNode(op):
            try validateMove(op)
        case let .replaceSubtree(op):
            try validateReplaceSubtree(op)
        case let .updateCommon(op):
            try requireNode(op.nodeID)
        case let .updateKind(op):
            try requireNode(op.nodeID)
        case let .setProperties(op):
            _ = try patchedNode(for: op)
        case let .overrideDescendant(op):
            try validateOverride(op)
        case let .overrideRoot(op):
            try validateRootOverride(op)
        case let .detachRef(op):
            try requireRef(op.refNodeID)
        case let .addVariable(op):
            try requireNoVariable(op.name)
        case let .updateVariable(op):
            try requireVariable(op.name)
        case let .removeVariable(op):
            try requireVariable(op.name)
        case let .addImport(op):
            try requireNoImport(op.alias)
        case let .updateImport(op):
            try requireImport(op.alias)
        case let .removeImport(op):
            try requireImport(op.alias)
        case let .addThemeAxis(op):
            try requireNoThemeAxis(op.name)
        case let .updateThemeAxis(op):
            try requireThemeAxis(op.name)
        case let .removeThemeAxis(op):
            try requireThemeAxis(op.name)
        }
    }

    // MARK: - Nodes

    /// The node with this id, refusing an id the document does not hold.
    ///
    /// - Parameter nodeID: The id to look up.
    /// - Returns: The node.
    /// - Throws: ``EditingError/nodeNotFound(id:)``.
    @discardableResult
    func requireNode(_ nodeID: String) throws -> PenNode {
        guard let node = nodes[nodeID] else {
            throw EditingError.nodeNotFound(id: nodeID)
        }
        return node
    }

    /// The node with this id together with its `ref` payload.
    ///
    /// - Parameter nodeID: The id of the ref node.
    /// - Returns: The node and the ref data it carries.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    @discardableResult
    func requireRef(_ nodeID: String) throws -> (node: PenNode, data: PenNode.RefData) {
        let node = try requireNode(nodeID)
        guard case let .ref(data) = node.kind else {
            throw EditingError.notARefNode(id: nodeID)
        }
        return (node, data)
    }

    /// Refuses an id already in the document, or used twice in the subtree itself.
    ///
    /// A subtree can carry ids that collide only with each other, which the document
    /// cannot see by looking at its own store — so the walk carries what it has seen.
    ///
    /// - Parameter node: The subtree about to be inserted.
    /// - Throws: ``EditingError/duplicateNodeID(id:)``.
    func validateNoDuplicateIDs(in node: PenNode) throws {
        var seen = Set<String>()
        try validateNoDuplicateIDs(in: node, seen: &seen)
    }

    /// Refuses a duplicate id, remembering the ids already met in this subtree.
    ///
    /// - Parameters:
    ///   - node: The node to check, then its inline children.
    ///   - seen: The ids met so far in this subtree.
    /// - Throws: ``EditingError/duplicateNodeID(id:)``.
    private func validateNoDuplicateIDs(in node: PenNode, seen: inout Set<String>) throws {
        guard nodes[node.id] == nil, seen.insert(node.id).inserted else {
            throw EditingError.duplicateNodeID(id: node.id)
        }
        for child in node.kind.inlineChildren {
            try validateNoDuplicateIDs(in: child, seen: &seen)
        }
    }

    // MARK: - Structural operations

    /// Checks an insert: no id collides, the parent exists and can hold children,
    /// and the index addresses a position in its list.
    ///
    /// - Parameter op: The insert to check.
    /// - Throws: ``EditingError/duplicateNodeID(id:)``, ``EditingError/parentNotFound(id:)``,
    ///   ``EditingError/cannotHaveChildren(parentID:)`` or ``EditingError/invalidIndex(index:count:)``.
    func validateInsert(_ op: EditOperation.InsertNode) throws {
        try validateNoDuplicateIDs(in: op.node)
        guard let parentID = op.parentID else {
            return try validateIndex(op.index, count: rootOrder.count)
        }
        try requireContainer(parentID)
        try validateIndex(op.index, count: children[parentID]?.count ?? 0)
    }

    /// Checks a delete: the node exists, and it strands no component instance the
    /// operation is not allowed to detach.
    ///
    /// - Parameter op: The delete to check.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or
    ///   ``EditingError/componentHasInstances(componentID:instanceIDs:)``.
    func validateDelete(_ op: EditOperation.DeleteNode) throws {
        try requireNode(op.nodeID)
        _ = try instancesToDetach(for: op)
    }

    /// Checks a move: the node and its target parent exist, the parent can hold
    /// children and is not inside the node, and the index addresses a position in
    /// the list the node will land in.
    ///
    /// - Parameter op: The move to check.
    /// - Throws: ``EditingError/nodeNotFound(id:)``, ``EditingError/parentNotFound(id:)``,
    ///   ``EditingError/cannotHaveChildren(parentID:)``, ``EditingError/wouldCreateCycle(nodeID:targetParentID:)``
    ///   or ``EditingError/invalidIndex(index:count:)``.
    func validateMove(_ op: EditOperation.MoveNode) throws {
        try requireNode(op.nodeID)
        if let newParentID = op.newParentID {
            try requireContainer(newParentID)
            if newParentID == op.nodeID || isDescendant(newParentID, of: op.nodeID) {
                throw EditingError.wouldCreateCycle(nodeID: op.nodeID, targetParentID: newParentID)
            }
        }
        try validateIndex(op.index, count: destinationCount(for: op))
    }

    /// Checks an override: the node is a `ref`, the key names something its component
    /// actually contains, and every value is one that node can take.
    ///
    /// - Parameter op: The override to check.
    /// - Throws: ``EditingError/nodeNotFound(id:)``, ``EditingError/notARefNode(id:)``,
    ///   ``EditingError/overrideTargetNotFound(refID:descendantKey:candidates:)`` or
    ///   ``EditingError/overrideValueRejected(refID:descendantKey:key:expected:actual:)``.
    func validateOverride(_ op: EditOperation.OverrideDescendant) throws {
        try requireRef(op.refNodeID)
        try validateOverrideTarget(op)
        try validateOverrideValues(op)
    }

    /// Checks a root override: the node is a `ref`, no key is one the ref reserves for
    /// itself, and every value is one the component's root node can take.
    ///
    /// - Parameter op: The root override to check.
    /// - Throws: ``EditingError/nodeNotFound(id:)``, ``EditingError/notARefNode(id:)``,
    ///   ``EditingError/rootOverrideKeyReserved(refID:key:reason:)`` or
    ///   ``EditingError/rootOverrideValueRejected(refID:key:expected:actual:)``.
    func validateRootOverride(_ op: EditOperation.OverrideRoot) throws {
        try requireRef(op.refNodeID)
        try validateRootOverrideKeys(op)
        try validateRootOverrideValues(op)
    }

    /// The node with this id, refusing one that cannot hold children.
    ///
    /// Reported as a *parent* problem — this is only ever asked about a node another
    /// node is being placed inside.
    ///
    /// - Parameter parentID: The prospective parent's id.
    /// - Throws: ``EditingError/parentNotFound(id:)`` or ``EditingError/cannotHaveChildren(parentID:)``.
    private func requireContainer(_ parentID: String) throws {
        guard let parent = nodes[parentID] else {
            throw EditingError.parentNotFound(id: parentID)
        }
        guard parent.kind.canHaveChildren else {
            throw EditingError.cannotHaveChildren(parentID: parentID)
        }
    }

    /// Refuses an index that does not address a position in a list of `count`.
    ///
    /// `nil` means "append", which is always in range.
    ///
    /// - Parameters:
    ///   - index: The requested position, or `nil` to append.
    ///   - count: The length of the list the node will land in.
    /// - Throws: ``EditingError/invalidIndex(index:count:)``.
    private func validateIndex(_ index: Int?, count: Int) throws {
        guard let index else { return }
        guard index >= 0, index <= count else {
            throw EditingError.invalidIndex(index: index, count: count)
        }
    }

    /// The length the destination list will have once the node has left its old one.
    ///
    /// A move within one parent shortens the very list it lands in, so the last valid
    /// index is one lower than that list's current length.
    private func destinationCount(for op: EditOperation.MoveNode) -> Int {
        let destination: [String] = if let newParentID = op.newParentID {
            children[newParentID] ?? []
        } else {
            rootOrder
        }
        guard parents[op.nodeID] == op.newParentID else { return destination.count }
        return destination.count - destination.count(where: { $0 == op.nodeID })
    }

    // MARK: - Document-level entries

    /// Refuses a variable name the document does not define.
    ///
    /// - Parameter name: The variable name.
    /// - Throws: ``EditingError/variableNotFound(name:)``.
    func requireVariable(_ name: String) throws {
        guard variables?[name] != nil else {
            throw EditingError.variableNotFound(name: name)
        }
    }

    /// Refuses a variable name the document already defines.
    ///
    /// - Parameter name: The variable name.
    /// - Throws: ``EditingError/variableAlreadyExists(name:)``.
    func requireNoVariable(_ name: String) throws {
        if variables?[name] != nil {
            throw EditingError.variableAlreadyExists(name: name)
        }
    }

    /// Refuses an import alias the document does not define.
    ///
    /// - Parameter alias: The import alias.
    /// - Throws: ``EditingError/importNotFound(alias:)``.
    func requireImport(_ alias: String) throws {
        guard imports?[alias] != nil else {
            throw EditingError.importNotFound(alias: alias)
        }
    }

    /// Refuses an import alias the document already defines.
    ///
    /// - Parameter alias: The import alias.
    /// - Throws: ``EditingError/importAlreadyExists(alias:)``.
    func requireNoImport(_ alias: String) throws {
        if imports?[alias] != nil {
            throw EditingError.importAlreadyExists(alias: alias)
        }
    }

    /// Refuses a theme axis the document does not define.
    ///
    /// - Parameter name: The theme axis name.
    /// - Throws: ``EditingError/themeAxisNotFound(name:)``.
    func requireThemeAxis(_ name: String) throws {
        guard themes?[name] != nil else {
            throw EditingError.themeAxisNotFound(name: name)
        }
    }

    /// Refuses a theme axis the document already defines.
    ///
    /// - Parameter name: The theme axis name.
    /// - Throws: ``EditingError/themeAxisAlreadyExists(name:)``.
    func requireNoThemeAxis(_ name: String) throws {
        if themes?[name] != nil {
            throw EditingError.themeAxisAlreadyExists(name: name)
        }
    }
}
