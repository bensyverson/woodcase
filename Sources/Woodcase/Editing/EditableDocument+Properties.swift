//
//  EditableDocument+Properties.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Checks an ``EditOperation/UpdateCommon``: the node exists, and the new common
    /// properties make no component that closes a loop.
    ///
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or
    ///   ``EditingError/wouldCloseComponentLoop(path:)``.
    func validateUpdateCommon(_ op: EditOperation.UpdateCommon) throws {
        try requireNode(op.nodeID)
        try refuseComponentLoops(closedBy: .updateCommon(op))
    }

    /// Applies an ``EditOperation/UpdateCommon`` operation.
    func applyUpdateCommon(_ op: EditOperation.UpdateCommon) throws {
        try validateUpdateCommon(op)
        var node = try requireNode(op.nodeID)
        let oldCommon = node.common
        node.common = op.common
        nodes[op.nodeID] = node
        updateComponentRegistry(for: op.nodeID)

        // Invalidate layout cache based on what changed
        if let category = ChangeCategory.categorize(oldCommon: oldCommon, newCommon: op.common) {
            invalidateLayoutCache(for: op.nodeID, category: category, subtree: oldCommon.theme != op.common.theme)
        }
    }

    /// Checks an ``EditOperation/UpdateKind``: a retype to a leaf needs the node to
    /// hold no children, and a leaf cannot declare an empty list.
    ///
    /// - Throws: ``EditingError/nodeNotFound(id:)``,
    ///   ``EditingError/cannotHaveChildren(parentID:)`` or
    ///   ``EditingError/wouldCloseComponentLoop(path:)``.
    func validateUpdateKind(_ op: EditOperation.UpdateKind) throws {
        try requireNode(op.nodeID)
        if !op.kind.canHaveChildren {
            guard (children[op.nodeID] ?? []).isEmpty, op.emptyChildren != .declared else {
                throw EditingError.cannotHaveChildren(parentID: op.nodeID)
            }
        }
        try refuseComponentLoops(closedBy: .updateKind(op))
    }

    /// Applies an ``EditOperation/UpdateKind`` operation.
    func applyUpdateKind(_ op: EditOperation.UpdateKind) throws {
        try validateUpdateKind(op)
        var node = try requireNode(op.nodeID)
        let oldKind = node.kind
        // Strip children from the provided kind to preserve flat store invariant
        node.kind = op.kind.withEmptyChildren()
        nodes[op.nodeID] = node
        updateComponentRegistry(for: op.nodeID)
        if !op.kind.canHaveChildren {
            children[op.nodeID] = nil
        } else if let empty = op.emptyChildren, (children[op.nodeID] ?? []).isEmpty {
            children[op.nodeID] = empty == .declared ? [] : nil
        }

        // Invalidate layout cache based on what changed
        if let category = ChangeCategory.categorize(oldKind: oldKind, newKind: op.kind.withEmptyChildren()) {
            invalidateLayoutCache(for: op.nodeID, category: category)
        }
    }

    /// The node a patch would produce, resolved against ``NodePropertyCodec``.
    ///
    /// Every key and value is checked here, on a copy, so ``validate(_:)`` and
    /// ``applySetProperties(_:)`` refuse exactly the same patches and nothing is
    /// written until the whole patch has been accepted.
    ///
    /// - Parameters:
    ///   - op: The patch to resolve.
    ///   - base: The node to patch in place of the stored one: an earlier preview of it
    ///     (``previewNodes(for:)``); `nil` patches the node as it stands.
    /// - Returns: The node as it stands and the node the patch would produce.
    /// - Throws: ``EditingError/nodeNotFound(id:)``,
    ///   ``EditingError/unknownProperty(nodeID:key:nodeType:)`` or
    ///   ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    func patchedNode(
        for op: EditOperation.SetProperties, onto base: PenNode? = nil
    ) throws -> (old: PenNode, new: PenNode) {
        let oldNode = try requireNode(op.nodeID)
        var newNode = base ?? oldNode
        for (path, value) in op.properties {
            newNode = try NodePropertyCodec.setting(value, at: path, on: newNode)
        }
        return (oldNode, newNode)
    }

    /// Checks a ``EditOperation/SetProperties``: every key and value resolves, and the
    /// patched node closes no component loop.
    ///
    /// - Parameters:
    ///   - op: The patch to check.
    ///   - base: The node to patch in place of the stored one; `nil` for the stored one.
    /// - Returns: The node as it stands and the node the patch would produce.
    /// - Throws: Whatever ``patchedNode(for:onto:)`` throws, or
    ///   ``EditingError/wouldCloseComponentLoop(path:)``.
    func validateSetProperties(
        _ op: EditOperation.SetProperties, onto base: PenNode? = nil
    ) throws -> (old: PenNode, new: PenNode) {
        let patch = try patchedNode(for: op, onto: base)
        try refuseComponentLoops(closedBy: .setProperties(op))
        return patch
    }

    /// Applies an ``EditOperation/SetProperties`` operation.
    ///
    /// Every key and value is resolved against ``NodePropertyCodec`` on a copy of
    /// the node before anything is stored, so a map with one unknown key or one
    /// bad value throws without changing the document.
    func applySetProperties(_ op: EditOperation.SetProperties) throws {
        let (oldNode, patched) = try validateSetProperties(op)
        guard patched != oldNode else { return }
        var newNode = patched

        newNode.kind = newNode.kind.withEmptyChildren()
        nodes[op.nodeID] = newNode
        updateComponentRegistry(for: op.nodeID)

        let category = ChangeCategory.merge(
            ChangeCategory.categorize(oldCommon: oldNode.common, newCommon: newNode.common),
            ChangeCategory.categorize(oldKind: oldNode.kind, newKind: newNode.kind)
        )
        if let category {
            invalidateLayoutCache(
                for: op.nodeID, category: category, subtree: oldNode.common.theme != newNode.common.theme
            )
        }
    }
}

// MARK: - Layout Cache Invalidation

extension EditableDocument {
    /// Invalidates the layout cache for a node based on the change category.
    ///
    /// A layout change records the node and its spine. When expansion can carry the
    /// change into other boards — a node on the spine is a component, or something
    /// renders it by name — it also records every instance that draws the change
    /// (``layoutInstancesDrawing(_:)``), with its spine: the cache's dirty ids are source
    /// ids, and the instances lay the change out under other ids in other boards. Each
    /// instance is laid out whole and its ancestors again; the rest of its board answers
    /// from memory.
    ///
    /// - Parameters:
    ///   - nodeID: The node that changed.
    ///   - category: How its change bears on layout.
    ///   - subtree: Whether every descendant's layout can change too — a `theme` change.
    func invalidateLayoutCache(for nodeID: String, category: ChangeCategory, subtree: Bool = false) {
        guard let cache = _layoutCache else { return }
        switch category {
        case .renderOnly:
            cache.invalidateRender(nodeID)
        case .layout:
            let ancestorIDs = ancestors(of: nodeID)
            if subtree {
                cache.invalidateSubtreeLayout(nodeID, ancestors: ancestorIDs)
            } else {
                cache.invalidateLayout(nodeID, ancestors: ancestorIDs)
            }
            let referrers = componentReferrers
            let drawn = ([nodeID] + ancestorIDs).filter {
                nodes[$0]?.common.reusable == true || !referrers.referrers(of: $0).isEmpty
            }
            for ref in layoutInstancesDrawing(drawn) {
                cache.invalidateLayout(ref, ancestors: ancestors(of: ref))
            }
        case .structural:
            cache.invalidateAll()
        }
    }

    /// The instances that draw the given nodes: every `ref` whose expansion holds one of
    /// them, directly or through components nesting it.
    ///
    /// They are the refs in the nodes' revision closure (``revisionDependents(of:)``), so
    /// it costs what the nodes reach rather than a pass over the document. Refs inside a
    /// component definition count, and so does a definition that is itself a ref (an
    /// alias component): a canvas expansion (``PenRefExpander/Purpose/canvas``) lays
    /// every top-level definition out like a board, where such a ref expands under its
    /// own id. An export expansion strips the definitions, and there those ids name
    /// nothing, which costs nothing. Naming a ref in ``PenLayoutInvalidation/nodes`` lays
    /// out its instance whole, and its ancestors (``PenLayoutIndex/expandedIDs(for:)``).
    /// A ref whose target resolves to nothing yet is named too; it has no instance, so
    /// layout passes over it.
    ///
    /// - Parameter drawn: Nodes that are components, or are rendered by name.
    /// - Returns: The refs' source ids.
    func layoutInstancesDrawing(_ drawn: [String]) -> Set<String> {
        revisionDependents(of: drawn).filter { id in
            if case .ref = nodes[id]?.kind { return true }
            return false
        }
    }
}
