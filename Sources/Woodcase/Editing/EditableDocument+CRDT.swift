//
//  EditableDocument+CRDT.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Applies a local editing operation, updating both the flat store and CRDT state.
    ///
    /// Call this instead of ``apply(_:)`` when in collaborative mode. The returned
    /// operations should be sent to other peers for convergence.
    ///
    /// The operation is checked against ``validate(_:)`` *before* the CRDT sees it.
    /// `CRDTDocument` is a class that mutates eagerly — an operation handed to
    /// `processLocal` has already been recorded in the log and is on its way to the
    /// peers — so a refusal that arrived any later would replicate the edit it
    /// refused. Refusing first is what keeps the two in step: nothing is logged,
    /// nothing is written, and the caller gets the same ``EditingError``
    /// ``apply(_:)`` throws.
    ///
    /// - Parameter operation: The local edit operation.
    /// - Returns: CRDT operations to replicate to other peers.
    /// - Throws: ``EditingError`` if the operation fails validation.
    func applyLocal(_ operation: EditOperation) throws -> [CRDTOperation] {
        guard let crdtDocument else {
            try apply(operation)
            return []
        }

        try validate(operation)

        // Detach has no CRDT primitive: it is planned once — derived ids and all —
        // and decomposed into the delete + insert both the CRDT and the flat store
        // process identically.
        if case let .detachRef(detachOp) = operation {
            guard let plan = try detachPlans(for: [detachOp.refNodeID]).first else { return [] }
            return try applyLocalDetachRef(plan)
        }

        // Replace needs the same treatment for a different reason: the CRDT has no
        // whole-subtree primitive, so it is decomposed into the deletes, property
        // writes and inserts both peers already converge on.
        if case let .replaceSubtree(replaceOp) = operation {
            return try applyLocalReplaceSubtree(replaceOp)
        }

        // A delete that strands instances under `.detach` is behavior, not a guard:
        // the instances have to be detached as their own primitives so both peers
        // generate the same ids. `validate(_:)` has already refused the delete if it
        // strands instances it is not allowed to detach.
        if case let .deleteNode(deleteOp) = operation {
            let plans = try detachPlans(deleting: deleteOp)
            if !plans.isEmpty {
                return try applyLocalDetachingDelete(deleteOp, plans: plans)
            }
        }

        let ops = crdtDocument.processLocal(operation: operation, document: self)

        if ops.isEmpty {
            // Nothing to replicate — a no-op edit, a patch the CRDT declined to
            // encode, or a local-only operation: ``EditOperation/setDocumentProperties(_:)``
            // has no replicated register, so the root's fonts, version, file token and
            // extras change on this peer alone. The flat store still runs it.
            try apply(operation)
            return []
        }

        // A remote batch settles only what it touches, which is exact while the flat
        // store agrees with the CRDT. An edit that leaves its own footprint disagreeing
        // marks the store, so the next batch reconciles the whole document instead.
        var journal = FlatStoreJournal()
        journal.noteFootprint(of: operation, in: self)
        defer { notePlacementAfterLocalEdit(journal) }
        do {
            try apply(operation)
        } catch {
            // Unreachable while `validate(_:)` mirrors every guard `apply(_:)` enforces.
            // If one ever escapes it, the CRDT state is already mutated and replicated,
            // so the flat store is brought into line with it rather than left behind:
            // reconciliation handles parents/children/rootOrder, but nodes created by
            // processLocal must be added explicitly.
            let created: [PenNode] = ops.compactMap { op in
                if case let .createNode(p) = op.payload { p.node } else { nil }
            }
            invalidatingCaches(touching: created.map(\.id)) {
                for node in created {
                    nodes[node.id] = node
                }
                reconcileChildrenWithParents()
            }
        }
        return ops
    }

    /// Carries out one planned detach in CRDT mode by decomposing it into primitives.
    ///
    /// The plan was made once, with derived ids
    /// (``SubtreeIDPlan/detaching(_:refID:replica:avoiding:)``), so the CRDT and the flat
    /// store insert the same subtree, and the inverse prepared beforehand names it.
    ///
    /// - Parameter plan: The detach, from ``detachPlans(for:)``.
    /// - Returns: The CRDT operations to replicate, in application order.
    /// - Throws: Whatever the primitives throw.
    private func applyLocalDetachRef(_ plan: PlannedDetach) throws -> [CRDTOperation] {
        try requireRef(plan.refID)

        // Record the ref's position, then decompose into primitive operations.
        let parentID = parents[plan.refID]
        let index: Int? = if let parentID {
            children[parentID]?.firstIndex(of: plan.refID)
        } else {
            rootOrder.firstIndex(of: plan.refID)
        }
        let deleteOp = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: plan.refID))
        let insertOp = EditOperation.insertNode(EditOperation.InsertNode(
            node: plan.subtree, parentID: parentID, index: index
        ))

        // Process both through the normal applyLocal path
        var allOps = try applyLocal(deleteOp)
        try allOps.append(contentsOf: applyLocal(insertOp))
        return allOps
    }

    /// Handles a replace in CRDT mode by decomposing it into primitives.
    ///
    /// The CRDT replicates properties per path and structure per node; it has no
    /// operation for "this node is now that whole subtree". So a replace becomes the
    /// edits that add up to one: the old children go, the node's own common and kind
    /// data are written, and the new children are inserted in order. Every one of
    /// those is an operation both peers already converge on.
    ///
    /// The guards ran before any of it — ``applyLocal(_:)`` validates first — so the
    /// decomposition cannot be refused half way through by a rule the whole would have
    /// failed.
    ///
    /// - Parameter op: The replacement.
    /// - Returns: The CRDT operations to replicate, in application order.
    /// - Throws: Whatever the primitives throw.
    private func applyLocalReplaceSubtree(_ op: EditOperation.ReplaceSubtree) throws -> [CRDTOperation] {
        var ops: [CRDTOperation] = []
        for childID in children[op.node.id] ?? [] {
            try ops.append(contentsOf: applyLocal(.deleteNode(EditOperation.DeleteNode(nodeID: childID))))
        }
        try ops.append(contentsOf: applyLocal(.updateCommon(EditOperation.UpdateCommon(
            nodeID: op.node.id, common: op.node.common
        ))))
        try ops.append(contentsOf: applyLocal(.updateKind(EditOperation.UpdateKind(
            nodeID: op.node.id, kind: op.node.kind.withEmptyChildren()
        ))))
        // Neither update carries extras: the node takes its replacement's, which is
        // the one local write the extras register ever sees.
        if let crdtDocument, nodes[op.node.id]?.extras != op.node.extras {
            ops.append(contentsOf: crdtDocument.processLocalSetExtras(nodeID: op.node.id, extras: op.node.extras))
            invalidatingCaches(touching: [op.node.id]) {
                nodes[op.node.id]?.extras = op.node.extras
            }
        }
        for (index, child) in op.node.kind.inlineChildren.enumerated() {
            try ops.append(contentsOf: applyLocal(.insertNode(EditOperation.InsertNode(
                node: child, parentID: op.node.id, index: index
            ))))
        }
        return ops
    }

    /// Handles a detaching delete in CRDT mode by decomposing it into primitives.
    ///
    /// Each stranded instance goes through `applyLocalDetachRef`, the same planned path
    /// a plain detach uses, so both peers see the same ids — the ones
    /// ``prepareInverse(of:)`` named. The component then goes through an ordinary
    /// delete, which by then strands nothing — and would throw if it somehow still did.
    private func applyLocalDetachingDelete(
        _ op: EditOperation.DeleteNode,
        plans: [PlannedDetach]
    ) throws -> [CRDTOperation] {
        var ops: [CRDTOperation] = []
        for plan in plans {
            try ops.append(contentsOf: applyLocalDetachRef(plan))
        }
        var plainDelete = op
        plainDelete.instances = .refuse
        try ops.append(contentsOf: applyLocal(.deleteNode(plainDelete)))
        return ops
    }

    /// Applies a single remote CRDT operation, updating the flat store.
    ///
    /// The operation is processed by the ``CRDTDocument`` for conflict resolution.
    /// If the operation is rejected (e.g. stale timestamp, cycle-creating move),
    /// the flat store is not modified.
    ///
    /// After applying, what the operation placed is reconciled with the CRDT
    /// (``reconcileChildrenWithParents(after:)``) to handle cases where list CRDTs and
    /// the tree move CRDT disagree.
    ///
    /// - Parameter operation: The remote CRDT operation from another peer.
    func applyRemote(_ operation: CRDTOperation) {
        guard crdtDocument != nil else { return }
        var journal = FlatStoreJournal()
        guard !applyRemoteMutations(operation, journal: &journal).isEmpty else { return }
        reconcileChildrenWithParents(after: &journal)
        onRemoteChange?()
    }

    /// Applies a batch of remote CRDT operations.
    ///
    /// Each operation is processed individually through the CRDT conflict resolution
    /// pipeline. Operations that are rejected are silently skipped. A final
    /// reconciliation of what the batch placed ensures structural consistency.
    ///
    /// - Parameter operations: The remote CRDT operations to apply.
    func applyRemote(_ operations: [CRDTOperation]) {
        guard crdtDocument != nil else { return }
        var journal = FlatStoreJournal()
        for operation in operations {
            applyRemoteMutations(operation, journal: &journal)
        }
        reconcileChildrenWithParents(after: &journal)
        onRemoteChange?()
    }

    /// Runs one remote operation through the CRDT and writes what it accepted into the
    /// flat store, returning the mutations written.
    ///
    /// This is the step the batch `applyRemote` repeats. It does not reconcile the
    /// children lists with the parents; a caller applying a batch of these reconciles
    /// once after the last operation, as `applyRemote` does. Inside the library a
    /// ``DocumentSession`` uses the overload that keeps a ``FlatStoreJournal``, so the
    /// reconciliation and the change's invalidation read only what the batch wrote.
    ///
    /// - Parameter operation: The remote CRDT operation.
    /// - Returns: The mutations written, in order; empty when the CRDT rejected the
    ///   operation (a stale write, a cycle-creating move) or the document is not
    ///   collaborative.
    @discardableResult
    func applyRemoteMutations(_ operation: CRDTOperation) -> [DocumentMutation] {
        var journal = FlatStoreJournal()
        return applyRemoteMutations(operation, journal: &journal)
    }

    /// Returns CRDT operations not yet seen by the given vector clock.
    ///
    /// Use this to determine which operations to send to a peer that has
    /// the given clock state.
    ///
    /// - Parameter since: The recipient's vector clock state.
    /// - Returns: Operations to send, or an empty array if not in collaborative mode.
    func pendingOperations(since: VectorClock) -> [CRDTOperation] {
        guard let crdtDocument else { return [] }
        return crdtDocument.pendingOperations(since: since)
    }
}

// MARK: - Reconciliation

extension EditableDocument {
    /// Runs one remote operation through the CRDT and writes what it accepted into the
    /// flat store, noting every write in a batch's journal first.
    ///
    /// Every write a remote batch makes is noted before it lands, so the journal names
    /// the batch's whole footprint: what ``reconcileChildrenWithParents(after:)``
    /// settles and what a ``ChangeInvalidation/RemoteProbe`` compares.
    ///
    /// - Parameters:
    ///   - operation: The remote CRDT operation.
    ///   - journal: The batch's journal.
    /// - Returns: The mutations written, in order; empty when the CRDT rejected the
    ///   operation or the document is not collaborative.
    @discardableResult
    func applyRemoteMutations(_ operation: CRDTOperation, journal: inout FlatStoreJournal) -> [DocumentMutation] {
        guard let crdtDocument,
              let mutations = crdtDocument.processRemote(operation: operation, document: self)
        else { return [] }
        for mutation in mutations {
            journal.note(mutation, in: self)
            applyMutation(mutation)
        }
        return mutations
    }

    /// Ensures the ``children`` map is consistent with the ``parents`` map.
    ///
    /// After tree move operations, the list CRDTs (RGA) may have accepted
    /// operations that the tree move CRDT rejected. This method removes
    /// nodes from children lists that don't match their actual parent,
    /// and ensures each node appears in its correct parent's children list.
    ///
    /// This whole-document pass is the definition a remote batch's own reconciliation,
    /// ``reconcileChildrenWithParents(after:)``, reproduces over what the batch wrote, and
    /// the oracle the reconciliation fuzz holds it to. It names no subjects — it may
    /// reparent or reorder anywhere in the document — so it drops the whole revision and
    /// expansion caches. Only a local edit the CRDT logged but the flat store refused,
    /// which ``applyLocal(_:)`` guards against, still runs it.
    func reconcileChildrenWithParents() {
        var journal = FlatStoreJournal()
        reconcileWholeDocument(journal: &journal)
    }

    /// The whole-document pass, noting in a journal every parent link, children list and
    /// root order it changes, so a probe reading the journal sees them.
    ///
    /// - Parameter journal: The journal of the change the pass closes.
    func reconcileWholeDocument(journal: inout FlatStoreJournal) {
        _placementUnsettled = false
        _revisionCache?.invalidateAll()
        _expansionCache?.invalidateAll()
        if let crdtDocument {
            reconcileCRDT(crdtDocument, journal: &journal)
        } else {
            reconcileNonCRDT()
        }
    }

    /// CRDT-mode reconciliation. Uses the tree move CRDT as the authoritative
    /// source for parent assignments and RGA lists for ordering.
    private func reconcileCRDT(_ crdtDocument: CRDTDocument, journal: inout FlatStoreJournal) {
        // Step 1: Determine the correct parent for every live node.
        // Sources of truth (in priority order):
        //   1. Tree move CRDT parentMap — authoritative for any node it knows about
        //   2. Flat store parents — for newly created nodes not yet moved
        // Constraints:
        //   - Tombstoned parents are treated as nil (promote to root)
        //   - Parents not in the nodes dict are treated as nil
        for nodeID in nodes.keys {
            let resolvedParent: String? = if let treeEntry = crdtDocument.treeMove.parentMap[nodeID] {
                // Tree CRDT knows about this node
                if let parentID = treeEntry,
                   !crdtDocument.tombstones.contains(parentID),
                   nodes[parentID] != nil
                {
                    parentID
                } else {
                    nil
                }
            } else if let flatParent = parents[nodeID],
                      !crdtDocument.tombstones.contains(flatParent),
                      nodes[flatParent] != nil
            {
                // Not in tree CRDT (newly created, never moved) — use flat store
                flatParent
            } else {
                nil
            }

            if parents[nodeID] != resolvedParent {
                journal.noteParent(of: nodeID, in: self)
                parents[nodeID] = resolvedParent
            }
        }

        // Step 2: Build expected state from the corrected parents
        var expectedChildSets: [String: Set<String>] = [:]
        var expectedRootSet = Set<String>()

        for nodeID in nodes.keys {
            if let parentID = parents[nodeID] {
                expectedChildSets[parentID, default: []].insert(nodeID)
            } else {
                expectedRootSet.insert(nodeID)
            }
        }

        // Step 3: Rebuild rootOrder from RGA, filtered and deduplicated
        let rgaRoot = crdtDocument.childrenLists[CRDTDocument.rootListID]?.elements ?? []
        var seenRoot = Set<String>()
        var newRootOrder = rgaRoot.filter { nodeID in
            expectedRootSet.contains(nodeID) && seenRoot.insert(nodeID).inserted
        }
        // Deterministic fallback: sort root nodes not covered by the RGA
        // so that all peers produce the same order.
        for nodeID in expectedRootSet.sorted() where !seenRoot.contains(nodeID) {
            newRootOrder.append(nodeID)
        }
        if rootOrder != newRootOrder {
            journal.noteChildren(of: nil, in: self)
            rootOrder = newRootOrder
        }

        // Step 4: Rebuild children maps from per-parent RGA lists
        var newChildren: [String: [String]] = [:]
        for (listID, list) in crdtDocument.childrenLists where listID != CRDTDocument.rootListID {
            guard let expectedSet = expectedChildSets[listID] else { continue }
            var seen = Set<String>()
            let ordered = list.elements.filter { childID in
                expectedSet.contains(childID) && seen.insert(childID).inserted
            }
            if !ordered.isEmpty {
                newChildren[listID] = ordered
            }
            expectedChildSets[listID] = expectedSet.subtracting(seen)
        }
        // Handle children not covered by RGA lists (sorted for determinism)
        for (parentID, remaining) in expectedChildSets where !remaining.isEmpty {
            for childID in remaining.sorted() {
                newChildren[parentID, default: []].append(childID)
            }
        }
        // A live container that declared a children array keeps one, empty or not, so
        // a peer that removed the last child and the peers it told agree on the bytes.
        for parentID in children.keys where newChildren[parentID] == nil && nodes[parentID] != nil {
            newChildren[parentID] = []
        }
        for parentID in Set(children.keys).union(newChildren.keys) where children[parentID] != newChildren[parentID] {
            journal.noteChildren(of: parentID, in: self)
        }
        children = newChildren
    }

    /// Non-CRDT reconciliation. Simple filter and ensure consistency.
    private func reconcileNonCRDT() {
        for (nodeID, parentID) in parents {
            if nodes[parentID] == nil {
                parents[nodeID] = nil
            }
        }

        var expectedChildSets: [String: Set<String>] = [:]
        var expectedRootSet = Set<String>()
        for nodeID in nodes.keys {
            if let parentID = parents[nodeID] {
                expectedChildSets[parentID, default: []].insert(nodeID)
            } else {
                expectedRootSet.insert(nodeID)
            }
        }

        for (parentID, childIDs) in children {
            guard nodes[parentID] != nil else {
                children[parentID] = nil
                continue
            }
            // An emptied list stays declared, as it does for a local delete or move.
            var seen = Set<String>()
            children[parentID] = childIDs.filter { parents[$0] == parentID && seen.insert($0).inserted }
        }

        var seenRoot = Set<String>()
        rootOrder = rootOrder.filter { nodeID in
            parents[nodeID] == nil && nodes[nodeID] != nil && seenRoot.insert(nodeID).inserted
        }

        for (parentID, childSet) in expectedChildSets {
            for childID in childSet {
                if children[parentID] == nil {
                    children[parentID] = [childID]
                } else if !children[parentID]!.contains(childID) {
                    children[parentID]!.append(childID)
                }
            }
        }
        for nodeID in expectedRootSet where !rootOrder.contains(nodeID) {
            rootOrder.append(nodeID)
        }
    }
}

// MARK: - Mutation Application

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
        }
    }
}
