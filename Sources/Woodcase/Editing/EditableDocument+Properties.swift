//
//  EditableDocument+Properties.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Applies an ``EditOperation/UpdateCommon`` operation.
    func applyUpdateCommon(_ op: EditOperation.UpdateCommon) throws {
        var node = try requireNode(op.nodeID)
        let oldCommon = node.common
        node.common = op.common
        nodes[op.nodeID] = node
        updateComponentRegistry(for: op.nodeID)

        // Invalidate layout cache based on what changed
        if let category = ChangeCategory.categorize(oldCommon: oldCommon, newCommon: op.common) {
            invalidateLayoutCache(for: op.nodeID, category: category)
        }
    }

    /// Applies an ``EditOperation/UpdateKind`` operation.
    func applyUpdateKind(_ op: EditOperation.UpdateKind) throws {
        var node = try requireNode(op.nodeID)
        let oldKind = node.kind
        // Strip children from the provided kind to preserve flat store invariant
        node.kind = op.kind.withEmptyChildren()
        nodes[op.nodeID] = node
        updateComponentRegistry(for: op.nodeID)

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
    /// - Parameter op: The patch to resolve.
    /// - Returns: The node as it stands and the node the patch would produce.
    /// - Throws: ``EditingError/nodeNotFound(id:)``,
    ///   ``EditingError/unknownProperty(nodeID:key:nodeType:)`` or
    ///   ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    func patchedNode(for op: EditOperation.SetProperties) throws -> (old: PenNode, new: PenNode) {
        let oldNode = try requireNode(op.nodeID)
        var newNode = oldNode
        for (path, value) in op.properties {
            newNode = try NodePropertyCodec.setting(value, at: path, on: newNode)
        }
        return (oldNode, newNode)
    }

    /// Applies an ``EditOperation/SetProperties`` operation.
    ///
    /// Every key and value is resolved against ``NodePropertyCodec`` on a copy of
    /// the node before anything is stored, so a map with one unknown key or one
    /// bad value throws without changing the document.
    func applySetProperties(_ op: EditOperation.SetProperties) throws {
        let (oldNode, patched) = try patchedNode(for: op)
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
            invalidateLayoutCache(for: op.nodeID, category: category)
        }
    }
}

// MARK: - Layout Cache Invalidation

extension EditableDocument {
    /// Invalidates the layout cache for a node based on the change category.
    func invalidateLayoutCache(for nodeID: String, category: ChangeCategory) {
        guard let cache = _layoutCache else { return }
        switch category {
        case .renderOnly:
            cache.invalidateRender(nodeID)
        case .layout:
            let ancestorIDs = ancestors(of: nodeID)
            cache.invalidateLayout(nodeID, ancestors: ancestorIDs)
        case .structural:
            cache.invalidateAll()
        }
    }
}
