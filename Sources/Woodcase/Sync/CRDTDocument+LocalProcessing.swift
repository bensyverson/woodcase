//
//  CRDTDocument+LocalProcessing.swift
//  Woodcase
//

import Foundation

extension CRDTDocument {
    // MARK: - Local operation processing

    func makeOp(_ payload: CRDTOperation.Payload) -> CRDTOperation {
        operationLog.appendLocal(payload: payload)
    }

    /// Generates a position timestamp for RGA inserts from the operation log's clock.
    ///
    /// This ensures all timestamps come from a single source, avoiding divergence
    /// between the position timestamps and operation IDs.
    func nextPositionTimestamp() -> Timestamp {
        Timestamp(time: operationLog.clock.tick(), peerID: peerID)
    }

    func processLocalInsert(_ op: EditOperation.InsertNode, document: EditableDocument) -> [CRDTOperation] {
        // Don't create CRDT ops for duplicate node IDs
        guard document.nodes[op.node.id] == nil else { return [] }
        var ops: [CRDTOperation] = []

        // Collect all nodes in the subtree
        let allNodes = collectNodes(in: op.node)

        for node in allNodes {
            let parentID: String? = if node.id == op.node.id {
                op.parentID
            } else {
                // Find the parent within the subtree
                findParentInSubtree(of: node.id, in: op.node)
            }

            let strippedNode = PenNode(
                id: node.id, common: node.common, kind: node.kind.withEmptyChildren(), extras: node.extras
            )
            let createOp = makeOp(.createNode(CRDTOperation.CreateNode(node: strippedNode, parentID: parentID)))
            ops.append(createOp)
            propertyMaps[node.id] = LWWPropertyMap()

            // Register in tree move CRDT so all peers converge on the initial parent
            treeMove.applyMove(TreeMoveCRDT.MoveOp(
                timestamp: createOp.id,
                nodeID: node.id,
                newParentID: parentID
            ))

            // Add to the appropriate children list
            let listID = parentID ?? Self.rootListID
            if childrenLists[listID] == nil {
                childrenLists[listID] = RGAList<String>()
            }

            let afterPos: PositionID?
            if node.id == op.node.id, let index = op.index, index > 0 {
                afterPos = childrenLists[listID]?.positionID(atIndex: index - 1)
            } else if node.id == op.node.id, op.index == nil {
                // Append — after last element
                let count = childrenLists[listID]?.count ?? 0
                afterPos = count > 0 ? childrenLists[listID]?.positionID(atIndex: count - 1) : nil
            } else {
                // Subtree children: append after previous sibling
                let count = childrenLists[listID]?.count ?? 0
                afterPos = count > 0 ? childrenLists[listID]?.positionID(atIndex: count - 1) : nil
            }

            let insertTimestamp = nextPositionTimestamp()
            childrenLists[listID]?.insert(node.id, after: afterPos, timestamp: insertTimestamp)

            ops.append(makeOp(.listInsert(CRDTOperation.ListInsert(
                listID: listID,
                elementID: node.id,
                afterPositionID: afterPos,
                positionTimestamp: insertTimestamp
            ))))
        }

        return ops
    }

    func processLocalDelete(_ op: EditOperation.DeleteNode, document: EditableDocument) -> [CRDTOperation] {
        guard document.nodes[op.nodeID] != nil else { return [] }
        var ops: [CRDTOperation] = []

        // Collect all descendants
        let allIDs = collectDescendants(of: op.nodeID, document: document)

        for nodeID in allIDs {
            tombstones.insert(nodeID)
            ops.append(makeOp(.deleteNode(CRDTOperation.DeleteNode(nodeID: nodeID))))

            // Remove from all RGA lists. A node can have live entries in multiple
            // lists due to concurrent moves. Tombstone all of them so remote peers
            // converge on the same tombstone state.
            for (listID, posID) in findAllEntries(for: nodeID) {
                childrenLists[listID]?.delete(positionID: posID)
                ops.append(makeOp(.listDelete(CRDTOperation.ListDelete(
                    listID: listID,
                    positionID: posID
                ))))
            }
        }

        return ops
    }

    func processLocalMove(_ op: EditOperation.MoveNode, document: EditableDocument) -> [CRDTOperation] {
        guard document.nodes[op.nodeID] != nil else { return [] }
        var ops: [CRDTOperation] = []

        // Tree move — create the CRDTOp first so the local tree move uses
        // the same timestamp that remote peers will see (the operation's id).
        let treeMoveOp = makeOp(.treeMove(CRDTOperation.TreeMove(
            nodeID: op.nodeID,
            newParentID: op.newParentID
        )))
        let accepted = treeMove.applyMove(TreeMoveCRDT.MoveOp(
            timestamp: treeMoveOp.id,
            nodeID: op.nodeID,
            newParentID: op.newParentID
        ))
        ops.append(treeMoveOp)

        // If tree CRDT rejected the move (e.g. cycle), don't modify RGA lists.
        // The treeMove op is still sent for convergence during log rebuilds.
        guard accepted else { return ops }

        // Use tree CRDT parentMap as source of truth for the old parent
        let expectedOldListID: String = (treeMove.parentMap[op.nodeID] ?? nil) ?? Self.rootListID
        let oldEntry: (listID: String, positionID: PositionID)? = if let posID = findPositionID(for: op.nodeID, in: childrenLists[expectedOldListID] ?? RGAList<String>()) {
            (expectedOldListID, posID)
        } else {
            // Tree CRDT disagrees with RGA — search all lists
            findAllEntries(for: op.nodeID).first
        }

        // Determine new list and insertion position
        let newListID = op.newParentID ?? Self.rootListID
        if childrenLists[newListID] == nil {
            childrenLists[newListID] = RGAList<String>()
        }

        let afterPos: PositionID?
        if let index = op.index, index > 0 {
            afterPos = childrenLists[newListID]?.positionID(atIndex: index - 1)
        } else if op.index == nil {
            let count = childrenLists[newListID]?.count ?? 0
            afterPos = count > 0 ? childrenLists[newListID]?.positionID(atIndex: count - 1) : nil
        } else {
            afterPos = nil
        }

        let insertTs = nextPositionTimestamp()

        // Apply locally: tombstone source, insert into target
        if let (oldListID, posID) = oldEntry {
            childrenLists[oldListID]?.delete(positionID: posID)

            // Emit a single atomic listMove op
            ops.append(makeOp(.listMove(CRDTOperation.ListMove(
                sourceListID: oldListID,
                targetListID: newListID,
                positionID: posID,
                afterPositionID: afterPos,
                newPositionTimestamp: insertTs
            ))))
        }

        childrenLists[newListID]?.insert(op.nodeID, after: afterPos, timestamp: insertTs)

        return ops
    }

    func processLocalUpdateCommon(_ op: EditOperation.UpdateCommon, document: EditableDocument) -> [CRDTOperation] {
        guard let node = document.nodes[op.nodeID] else { return [] }

        let changedProps = PropertyDiff.diffCommon(old: node.common, new: op.common)
        var ops: [CRDTOperation] = []

        for property in changedProps {
            let value = extractCommonValue(property: property, from: op.common)
            let crdtOp = makeOp(.setProperty(CRDTOperation.SetProperty(
                nodeID: op.nodeID,
                property: property,
                value: value
            )))
            ops.append(crdtOp)

            // Record in property map
            if propertyMaps[op.nodeID] == nil {
                propertyMaps[op.nodeID] = LWWPropertyMap()
            }
            propertyMaps[op.nodeID]?.record(property: property, at: crdtOp.id)
        }

        return ops
    }

    func processLocalUpdateKind(_ op: EditOperation.UpdateKind, document: EditableDocument) -> [CRDTOperation] {
        guard let node = document.nodes[op.nodeID] else { return [] }

        let changedProps = PropertyDiff.diffKind(old: node.kind, new: op.kind)
        var ops: [CRDTOperation] = []

        for property in changedProps {
            let value = extractKindValue(property: property, from: op.kind)
            let crdtOp = makeOp(.setProperty(CRDTOperation.SetProperty(
                nodeID: op.nodeID,
                property: property,
                value: value
            )))
            ops.append(crdtOp)

            if propertyMaps[op.nodeID] == nil {
                propertyMaps[op.nodeID] = LWWPropertyMap()
            }
            propertyMaps[op.nodeID]?.record(property: property, at: crdtOp.id)
        }

        return ops
    }

    /// Emits one LWW ``CRDTOperation/SetProperty`` per path a patch names.
    ///
    /// ``EditableDocument/applyLocal(_:)`` has already refused a patch with an unknown
    /// key or a bad value before this is called. The resolve below is belt and braces
    /// for any other caller: a patch that will not resolve emits nothing rather than
    /// a half-replicated trail.
    func processLocalSetProperties(_ op: EditOperation.SetProperties, document: EditableDocument) -> [CRDTOperation] {
        guard let node = document.nodes[op.nodeID] else { return [] }

        // Resolve the whole patch before emitting anything, so a rejected patch
        // leaves no half-replicated trail.
        var patched = node
        for (path, value) in op.properties {
            guard let next = try? NodePropertyCodec.setting(value, at: path, on: patched) else { return [] }
            patched = next
        }

        var ops: [CRDTOperation] = []
        for (path, value) in op.properties {
            let normalized = (try? NodePropertyCodec.value(at: path, of: patched)) ?? value
            let crdtOp = makeOp(.setProperty(CRDTOperation.SetProperty(
                nodeID: op.nodeID,
                property: path,
                value: normalized
            )))
            ops.append(crdtOp)

            if propertyMaps[op.nodeID] == nil {
                propertyMaps[op.nodeID] = LWWPropertyMap()
            }
            propertyMaps[op.nodeID]?.record(property: path, at: crdtOp.id)
        }

        return ops
    }

    func processLocalOverrideDescendant(
        _ op: EditOperation.OverrideDescendant,
        document: EditableDocument
    ) -> [CRDTOperation] {
        guard let node = document.nodes[op.refNodeID] else { return [] }
        guard case var .ref(refData) = node.kind else { return [] }

        // Merge the override into the ref's descendants, then drop what it unsets
        var descendants = refData.descendants ?? [:]
        var existing = descendants[op.descendantID]?.properties ?? [:]
        existing.merge(op.properties) { _, new in new }
        for key in op.unset {
            existing.removeValue(forKey: key)
        }
        descendants[op.descendantID] = existing.isEmpty ? nil : PenDescendantOverride(properties: existing)
        refData.descendants = descendants.isEmpty ? nil : descendants

        // Delegate to processLocalUpdateKind — CRDT sees this as a kind.descendants change
        let newKind = PenNode.Kind.ref(refData)
        return processLocalUpdateKind(
            EditOperation.UpdateKind(nodeID: op.refNodeID, kind: newKind),
            document: document
        )
    }

    /// Records a root override as the `kind.rootOverrides` change the wire already has.
    ///
    /// The map is one CRDT property, exactly as `kind.descendants` is: a peer that
    /// writes one key and a peer that writes another converge on whichever wrote last,
    /// which is the granularity `set kind.rootOverrides=…` has always had.
    ///
    /// - Parameters:
    ///   - op: The root override applied locally.
    ///   - document: The document it was applied to.
    /// - Returns: The operations to broadcast, empty when the node is not a live ref.
    func processLocalOverrideRoot(
        _ op: EditOperation.OverrideRoot,
        document: EditableDocument
    ) -> [CRDTOperation] {
        guard let node = document.nodes[op.refNodeID] else { return [] }
        guard case var .ref(refData) = node.kind else { return [] }

        var overrides = refData.rootOverrides ?? [:]
        overrides.merge(op.properties) { _, new in new }
        for key in op.unset {
            overrides.removeValue(forKey: key)
        }
        refData.rootOverrides = overrides.isEmpty ? nil : overrides

        return processLocalUpdateKind(
            EditOperation.UpdateKind(nodeID: op.refNodeID, kind: .ref(refData)),
            document: document
        )
    }

    /// Generic local LWW handler: creates an op, records the timestamp, returns the op.
    func processLocalDocumentLWW(
        payload: CRDTOperation.Payload,
        key: String,
        timestamps: inout [String: Timestamp]
    ) -> [CRDTOperation] {
        let crdtOp = makeOp(payload)
        timestamps[key] = crdtOp.id
        return [crdtOp]
    }

    func processLocalSetVariable(name: String, variable: PenVariable) -> [CRDTOperation] {
        processLocalDocumentLWW(payload: .setVariable(CRDTOperation.SetVariable(name: name, variable: variable)), key: name, timestamps: &variableTimestamps)
    }

    func processLocalRemoveVariable(name: String) -> [CRDTOperation] {
        processLocalDocumentLWW(payload: .removeVariable(CRDTOperation.RemoveVariable(name: name)), key: name, timestamps: &variableTimestamps)
    }

    func processLocalSetImport(alias: String, path: String) -> [CRDTOperation] {
        processLocalDocumentLWW(payload: .setImport(CRDTOperation.SetImport(alias: alias, path: path)), key: alias, timestamps: &importTimestamps)
    }

    func processLocalRemoveImport(alias: String) -> [CRDTOperation] {
        processLocalDocumentLWW(payload: .removeImport(CRDTOperation.RemoveImport(alias: alias)), key: alias, timestamps: &importTimestamps)
    }

    func processLocalSetThemeAxis(name: String, options: [String]) -> [CRDTOperation] {
        processLocalDocumentLWW(payload: .setThemeAxis(CRDTOperation.SetThemeAxis(name: name, options: options)), key: name, timestamps: &themeTimestamps)
    }

    func processLocalRemoveThemeAxis(name: String) -> [CRDTOperation] {
        processLocalDocumentLWW(payload: .removeThemeAxis(CRDTOperation.RemoveThemeAxis(name: name)), key: name, timestamps: &themeTimestamps)
    }
}
