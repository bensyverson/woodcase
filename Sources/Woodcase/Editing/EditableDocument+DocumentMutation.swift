//
//  EditableDocument+DocumentMutation.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Applies a single ``DocumentMutation`` to the flat store.
    ///
    /// This is the bridge between the CRDT layer's conflict resolution output
    /// and the observable flat store. Each mutation case maps directly to
    /// a flat store update.
    ///
    /// It is also the choke point for remote editing — nothing a peer sends reaches
    /// the flat store except as a ``DocumentMutation`` — so the caches'
    /// invalidation rule wraps it, the way ``apply(_:)`` wraps the local path.
    func applyMutation(_ mutation: DocumentMutation) {
        invalidatingCaches(touching: subjects(of: mutation)) {
            applyMutationToStore(mutation)
        }
    }

    /// Writes one mutation into the flat store. Call ``applyMutation(_:)`` instead —
    /// it is what keeps the expansion and revision caches in step.
    ///
    /// - Parameter mutation: The mutation to write.
    private func applyMutationToStore(_ mutation: DocumentMutation) {
        switch mutation {
        case let .setNode(node):
            // Categorize the change for layout cache invalidation
            if let oldNode = nodes[node.id] {
                let commonCategory = ChangeCategory.categorize(oldCommon: oldNode.common, newCommon: node.common)
                let kindCategory = ChangeCategory.categorize(oldKind: oldNode.kind, newKind: node.kind.withEmptyChildren())
                let category = ChangeCategory.merge(commonCategory, kindCategory)
                if let category {
                    invalidateLayoutCache(
                        for: node.id, category: category, subtree: oldNode.common.theme != node.common.theme
                    )
                }
            } else {
                // New node via CRDT — structural change
                _layoutCache?.invalidateAll()
            }

            nodes[node.id] = node
            updateComponentRegistry(for: node.id)

        case let .removeNode(nodeID):
            _layoutCache?.invalidateAll()
            componentRegistry[nodeID] = nil
            nodes[nodeID] = nil
            children[nodeID] = nil
            // A parent left with no children keeps its declared empty array.
            if let parentID = parents[nodeID] {
                children[parentID]?.removeAll { $0 == nodeID }
            } else {
                rootOrder.removeAll { $0 == nodeID }
            }

        case let .setChildren(parentID, childIDs):
            // An emptied list stays declared; one that was never declared stays absent.
            if let parentID {
                if !childIDs.isEmpty || children[parentID] != nil {
                    children[parentID] = childIDs
                }
            } else {
                rootOrder = childIDs
            }

        case let .setParent(nodeID, parentID):
            // Remove from old parent first
            if let oldParentID = parents[nodeID] {
                children[oldParentID]?.removeAll { $0 == nodeID }
            } else if rootOrder.contains(nodeID) {
                rootOrder.removeAll { $0 == nodeID }
            }

            // Update parent pointer and add to new parent's children
            if let parentID {
                parents[nodeID] = parentID
                if children[parentID] == nil {
                    children[parentID] = [nodeID]
                } else if !children[parentID]!.contains(nodeID) {
                    children[parentID]!.append(nodeID)
                }
            } else {
                // Moving to root
                parents[nodeID] = nil
                if !rootOrder.contains(nodeID) {
                    rootOrder.append(nodeID)
                }
            }

        case let .removeParent(nodeID):
            parents[nodeID] = nil

        case let .setVariable(name, variable):
            if variables == nil { variables = [:] }
            variables?[name] = variable

        case let .removeVariable(name):
            variables?[name] = nil
            if variables?.isEmpty == true { variables = nil }

        case let .setImport(alias, path):
            if imports == nil { imports = [:] }
            imports?[alias] = path

        case let .removeImport(alias):
            imports?[alias] = nil
            if imports?.isEmpty == true { imports = nil }

        case let .setThemeAxis(name, options):
            if themes == nil { themes = [:] }
            themes?[name] = options

        case let .removeThemeAxis(name):
            themes?[name] = nil
            if themes?.isEmpty == true { themes = nil }

        case let .setDocumentProperty(key, value):
            // A write this replica cannot take — leaving out a table a concurrent write
            // has filled — leaves the root as it is, as a refused local patch would.
            try? applySetDocumentProperties(EditOperation.SetDocumentProperties(properties: [key: value]))
        }
    }
}
