//
//  CRDTDocument+RemoteProcessing.swift
//  Woodcase
//

import Foundation

extension CRDTDocument {
    // MARK: - Remote processing helpers

    func processRemoteSetProperty(_ p: CRDTOperation.SetProperty, timestamp: Timestamp, document: EditableDocument) -> [DocumentMutation]? {
        // A write to a deleted node is kept for its return (see CRDTDocument+Existence).
        guard !tombstones.contains(p.nodeID) else {
            keepDormant(p, at: timestamp)
            return nil
        }
        guard document.nodes[p.nodeID] != nil else { return nil }
        // The create that brought the node into being wrote every property it carries.
        guard postdatesExistence(of: p.nodeID, at: timestamp) else { return nil }

        if propertyMaps[p.nodeID] == nil {
            propertyMaps[p.nodeID] = LWWPropertyMap()
        }

        guard propertyMaps[p.nodeID]!.shouldAccept(property: p.property, at: timestamp) else { return nil }
        propertyMaps[p.nodeID]!.record(property: p.property, at: timestamp)

        return [.setNode(applyPropertyToNode(
            nodeID: p.nodeID,
            property: p.property,
            value: p.value,
            document: document
        ))]
    }

    func processRemoteListInsert(_ p: CRDTOperation.ListInsert) -> [DocumentMutation]? {
        if childrenLists[p.listID] == nil {
            childrenLists[p.listID] = RGAList<String>()
        }
        childrenLists[p.listID]?.insert(p.elementID, after: p.afterPositionID, timestamp: p.positionTimestamp)

        let childIDs = childrenLists[p.listID]?.elements ?? []
        let parentID: String? = p.listID == Self.rootListID ? nil : p.listID
        return [.setChildren(parentID: parentID, childIDs: childIDs)]
    }

    func processRemoteListDelete(_ p: CRDTOperation.ListDelete) -> [DocumentMutation]? {
        childrenLists[p.listID]?.delete(positionID: p.positionID)

        let childIDs = childrenLists[p.listID]?.elements ?? []
        let parentID: String? = p.listID == Self.rootListID ? nil : p.listID
        return [.setChildren(parentID: parentID, childIDs: childIDs)]
    }

    func processRemoteListMove(_ p: CRDTOperation.ListMove) -> [DocumentMutation]? {
        // Look up the element value before tombstoning
        guard let element = childrenLists[p.sourceListID]?.value(at: p.positionID) else {
            return nil
        }

        // Tombstone in source
        childrenLists[p.sourceListID]?.delete(positionID: p.positionID)

        // Insert into target
        if childrenLists[p.targetListID] == nil {
            childrenLists[p.targetListID] = RGAList<String>()
        }
        childrenLists[p.targetListID]?.insert(element, after: p.afterPositionID, timestamp: p.newPositionTimestamp)

        let sourceChildIDs = childrenLists[p.sourceListID]?.elements ?? []
        let targetChildIDs = childrenLists[p.targetListID]?.elements ?? []
        let sourceParent: String? = p.sourceListID == Self.rootListID ? nil : p.sourceListID
        let targetParent: String? = p.targetListID == Self.rootListID ? nil : p.targetListID

        return [
            .setChildren(parentID: sourceParent, childIDs: sourceChildIDs),
            .setChildren(parentID: targetParent, childIDs: targetChildIDs),
        ]
    }

    func processRemoteTreeMove(_ p: CRDTOperation.TreeMove, timestamp: Timestamp, document _: EditableDocument) -> [DocumentMutation]? {
        let oldParentMap = treeMove.parentMap

        // Always let the tree CRDT process the move — all replicas must see the
        // same operations to converge. Tombstone handling is applied to the mutations,
        // not to the tree CRDT input.
        treeMove.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: timestamp,
            nodeID: p.nodeID,
            newParentID: p.newParentID
        ))
        let newParentMap = treeMove.parentMap

        // Full reconciliation: emit mutations for every changed parent relationship.
        // This is necessary because applyMove may trigger a full log replay (rebuild)
        // that reorders earlier operations and changes multiple parent entries.
        var mutations: [DocumentMutation] = []

        for (nodeID, newParentOpt) in newParentMap {
            // Skip nodes that are explicitly tombstoned (received a deleteNode op).
            guard !tombstones.contains(nodeID) else { continue }

            // Distinguish "not in old map" (new to tree CRDT) from "in old map with nil" (was at root).
            let wasInOldMap = oldParentMap.keys.contains(nodeID)
            let oldParentOpt: String? = wasInOldMap ? (oldParentMap[nodeID] ?? nil) : nil
            let changed = !wasInOldMap || newParentOpt != oldParentOpt
            guard changed else { continue }

            if let newParent = newParentOpt, !tombstones.contains(newParent) {
                mutations.append(.setParent(nodeID: nodeID, parentID: newParent))
            } else {
                // New parent is nil (root) or tombstoned — place at root.
                // Reconciliation will handle any further adjustments.
                mutations.append(.setParent(nodeID: nodeID, parentID: nil))
            }
        }

        return mutations.isEmpty ? nil : mutations
    }

    func processRemoteCreateNode(
        _ p: CRDTOperation.CreateNode, timestamp: Timestamp, document: EditableDocument
    ) -> [DocumentMutation]? {
        let strippedNode = PenNode(
            id: p.node.id, common: p.node.common, kind: p.node.kind.withEmptyChildren(), extras: p.node.extras
        )

        // Register in tree move CRDT so all peers converge on the initial parent.
        // This uses the CRDTOperation's id, which is the same timestamp the sender
        // used when processing locally — ensuring tree CRDT state converges. Every
        // create's move is taken, whether or not the create wins the node's existence
        // register, so every replica's tree sees the same moves.
        let placed = treeMove.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: timestamp,
            nodeID: p.node.id,
            newParentID: p.parentID
        ))

        // A create older than the id's latest create or delete loses to it.
        guard postdatesExistence(of: p.node.id, at: timestamp) else { return nil }
        let held = tombstones.contains(p.node.id) ? nil : document.nodes[p.node.id]
        recordExistence(of: p.node.id, alive: true, at: timestamp, holding: held)

        var mutations: [DocumentMutation] = [.setNode(applyingDormantWrites(to: strippedNode))]

        // If the parent is tombstoned, create at root instead — the reconciliation
        // pass will finalize placement. This avoids cascade-tombstoning nodes that
        // a concurrent peer created or moved, which would cause divergence. A parent the
        // tree refused (the node itself, or one of its descendants) is never written:
        // a node the tree does not place keeps its flat-store parent, so writing it
        // would close a parent cycle in the flat store.
        if placed, let parentID = p.parentID, !tombstones.contains(parentID) {
            mutations.append(.setParent(nodeID: p.node.id, parentID: parentID))
        }

        return mutations
    }

    func processRemoteDeleteNode(
        _ p: CRDTOperation.DeleteNode, timestamp: Timestamp, document: EditableDocument
    ) -> [DocumentMutation]? {
        // A delete older than the id's latest create or delete loses to it: an undone
        // delete's node stays back.
        guard postdatesExistence(of: p.nodeID, at: timestamp) else { return nil }
        let wasDeleted = tombstones.contains(p.nodeID)
        recordExistence(of: p.nodeID, alive: false, at: timestamp, holding: wasDeleted ? nil : document.nodes[p.nodeID])
        guard !wasDeleted else { return nil }
        // Only tombstone the specific node — don't cascade on the receiver side.
        // The originator sends individual deleteNode ops for each descendant,
        // so cascading here would double-delete and could incorrectly capture
        // nodes that were concurrently moved INTO the subtree by another peer.
        return [
            .removeNode(nodeID: p.nodeID),
            .removeParent(nodeID: p.nodeID),
        ]
    }

    /// Generic remote LWW handler: checks timestamp, records if accepted, returns mutation.
    func processRemoteDocumentLWW(
        key: String,
        timestamp: Timestamp,
        timestamps: inout [String: Timestamp],
        mutation: DocumentMutation
    ) -> [DocumentMutation]? {
        if let existing = timestamps[key], existing >= timestamp { return nil }
        timestamps[key] = timestamp
        return [mutation]
    }

    func processRemoteSetVariable(_ p: CRDTOperation.SetVariable, timestamp: Timestamp) -> [DocumentMutation]? {
        processRemoteDocumentLWW(key: p.name, timestamp: timestamp, timestamps: &variableTimestamps, mutation: .setVariable(name: p.name, variable: p.variable))
    }

    func processRemoteRemoveVariable(_ p: CRDTOperation.RemoveVariable, timestamp: Timestamp) -> [DocumentMutation]? {
        processRemoteDocumentLWW(key: p.name, timestamp: timestamp, timestamps: &variableTimestamps, mutation: .removeVariable(name: p.name))
    }

    func processRemoteSetImport(_ p: CRDTOperation.SetImport, timestamp: Timestamp) -> [DocumentMutation]? {
        processRemoteDocumentLWW(key: p.alias, timestamp: timestamp, timestamps: &importTimestamps, mutation: .setImport(alias: p.alias, path: p.path))
    }

    func processRemoteRemoveImport(_ p: CRDTOperation.RemoveImport, timestamp: Timestamp) -> [DocumentMutation]? {
        processRemoteDocumentLWW(key: p.alias, timestamp: timestamp, timestamps: &importTimestamps, mutation: .removeImport(alias: p.alias))
    }

    func processRemoteSetThemeAxis(_ p: CRDTOperation.SetThemeAxis, timestamp: Timestamp) -> [DocumentMutation]? {
        processRemoteDocumentLWW(key: p.name, timestamp: timestamp, timestamps: &themeTimestamps, mutation: .setThemeAxis(name: p.name, options: p.options))
    }

    func processRemoteRemoveThemeAxis(_ p: CRDTOperation.RemoveThemeAxis, timestamp: Timestamp) -> [DocumentMutation]? {
        processRemoteDocumentLWW(key: p.name, timestamp: timestamp, timestamps: &themeTimestamps, mutation: .removeThemeAxis(name: p.name))
    }
}
