//
//  EditableDocument+Replace.swift
//  Woodcase
//

import Foundation

/// Replacing a subtree in place: the "rebuild this node" edit, as one operation.
///
/// A delete followed by an insert would do the same to the file and the wrong thing to
/// everything that names the node: the id would change, the node would lose its place
/// among its siblings, and a reusable definition would strand every instance of itself
/// on the way through. So the node's *slot* — its id, its parent and its index — is
/// exactly what this operation does not touch.
extension EditableDocument {
    /// Swaps everything under a node for a new subtree, keeping the node's place.
    ///
    /// - Parameter op: The replacement, carrying the id of the node it replaces.
    /// - Throws: Whatever ``validateReplaceSubtree(_:)`` refuses.
    func applyReplaceSubtree(_ op: EditOperation.ReplaceSubtree) throws {
        try validateReplaceSubtree(op)

        let rootID = op.node.id
        let parentID = parents[rootID]
        for id in descendantIDs(of: rootID) {
            componentRegistry[id] = nil
            nodes[id] = nil
            children[id] = nil
            parents[id] = nil
        }

        writeSubtree(op.node, parentID: parentID)
        for id in collectInsertedIDs(in: op.node) {
            updateComponentRegistry(for: id)
        }
        _layoutCache?.invalidateAll()
    }

    /// Checks a replacement: the node exists, the ids fit, and nothing outside the
    /// subtree loses what it points at.
    ///
    /// - Parameter op: The replacement to check.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` for a node the document does not
    ///   hold, ``EditingError/invalidNodeID(id:)`` or
    ///   ``EditingError/duplicateNodeID(id:)`` for an id the subtree cannot have,
    ///   ``EditingError/componentHasInstances(componentID:instanceIDs:)`` when the
    ///   replacement would strand a component's instances, or
    ///   ``EditingError/componentTypeChange(componentID:from:to:instanceIDs:)`` for a
    ///   whole-kind swap on a definition that instances point at.
    func validateReplaceSubtree(_ op: EditOperation.ReplaceSubtree) throws {
        let existing = try requireNode(op.node.id)
        let freed = Set(descendantIDs(of: op.node.id))
        var seen = Set<String>()
        try validateReplacementIDs(op.node, freed: freed, seen: &seen)
        try requireNothingStranded(by: op.node.id, freed: freed)
        try requireStableType(of: existing, replacedBy: op.node, freed: freed)
    }

    // MARK: - Writing

    /// Writes a subtree into the flat store beneath an existing parent.
    ///
    /// Unlike the insert path, this keeps the difference between a container that
    /// declares no children and one that declares an empty list: a node written with
    /// `"children": []` reads back that way, which is what lets an undo restore the
    /// bytes the file had rather than merely an equivalent tree.
    ///
    /// - Parameters:
    ///   - node: The subtree to write.
    ///   - parentID: The parent to record for its root, or `nil` for a root node.
    private func writeSubtree(_ node: PenNode, parentID: String?) {
        nodes[node.id] = PenNode(
            id: node.id, common: node.common, kind: node.kind.withEmptyChildren(), extras: node.extras
        )
        if let parentID {
            parents[node.id] = parentID
        }
        if let declared = node.kind.declaredChildIDs {
            children[node.id] = declared
        }
        for child in node.kind.inlineChildren {
            writeSubtree(child, parentID: node.id)
        }
    }

    // MARK: - Ids

    /// Checks every id in a replacement subtree.
    ///
    /// The ids the replaced subtree holds today are `freed`: they go away with it, so
    /// the replacement may keep any of them. Every other id has to be one the document
    /// does not already hold.
    ///
    /// - Parameters:
    ///   - node: The node to check, then its inline children.
    ///   - freed: The ids the replaced subtree is giving up.
    ///   - seen: The ids met so far in this subtree.
    /// - Throws: ``EditingError/invalidNodeID(id:)`` or ``EditingError/duplicateNodeID(id:)``.
    private func validateReplacementIDs(
        _ node: PenNode,
        freed: Set<String>,
        seen: inout Set<String>
    ) throws {
        guard PenID.isValid(node.id) else {
            throw EditingError.invalidNodeID(id: node.id)
        }
        guard nodes[node.id] == nil || freed.contains(node.id), seen.insert(node.id).inserted else {
            throw EditingError.duplicateNodeID(id: node.id)
        }
        for child in node.kind.inlineChildren {
            try validateReplacementIDs(child, freed: freed, seen: &seen)
        }
    }

    // MARK: - Consequence guards

    /// Refuses a replacement that would take away a component something still points at.
    ///
    /// The same rule a delete carries, scoped to the descendants: the node itself
    /// survives — that is the whole point of a replace — so only a definition *inside*
    /// the subtree can be stranded, and only by a `ref` that outlives it.
    ///
    /// - Parameters:
    ///   - rootID: The node being replaced.
    ///   - freed: The ids its subtree is giving up.
    /// - Throws: ``EditingError/componentHasInstances(componentID:instanceIDs:)``.
    private func requireNothingStranded(by rootID: String, freed: Set<String>) throws {
        for componentID in freed.subtracting([rootID]).filter({ componentRegistry[$0] != nil }).sorted() {
            let survivors = instanceIDs(ofComponent: componentID).filter { !freed.contains($0) }
            guard survivors.isEmpty else {
                throw EditingError.componentHasInstances(componentID: componentID, instanceIDs: survivors)
            }
        }
    }

    /// Refuses a whole-kind swap on a reusable definition that instances point at.
    ///
    /// Every instance expands the definition it names, so turning a `frame` component
    /// into a `text` one silently changes what every instance draws — and a type
    /// change does not converge between peers, because the replication layer patches
    /// properties per path and no path can carry a node's type (see the kind-swap
    /// entry in `project/backlog.md`). Rebuilding the definition's *contents* is fine
    /// and is what this verb is for; changing what kind of thing it is, is not.
    ///
    /// - Parameters:
    ///   - existing: The node as the document holds it.
    ///   - replacement: The subtree taking its place.
    ///   - freed: The ids the replaced subtree is giving up, so an instance living
    ///     inside it does not count — it is going away too.
    /// - Throws: ``EditingError/componentTypeChange(componentID:from:to:instanceIDs:)``.
    private func requireStableType(
        of existing: PenNode,
        replacedBy replacement: PenNode,
        freed: Set<String>
    ) throws {
        guard existing.common.reusable == true else { return }
        guard existing.kind.typeName != replacement.kind.typeName else { return }
        let instances = instanceIDs(ofComponent: existing.id).filter { !freed.contains($0) }
        guard instances.isEmpty else {
            throw EditingError.componentTypeChange(
                componentID: existing.id,
                from: existing.kind.typeName,
                to: replacement.kind.typeName,
                instanceIDs: instances
            )
        }
    }
}
