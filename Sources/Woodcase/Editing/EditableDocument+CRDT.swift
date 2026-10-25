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
            // Nothing to replicate — a no-op edit, or a patch the CRDT declined to
            // encode. The flat store still runs it.
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

    /// Carries out one planned detach in CRDT mode by decomposing it into primitives:
    /// the ref's delete, the expansion's insert, and a kind write per connector whose
    /// ends it renames (``connectorRewrites(for:)``).
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

        // Process both through the normal applyLocal path, then the connector ends the
        // detach renames, so a peer receives them as part of the same change.
        let rewrites = connectorRewrites(for: plan)
        var allOps = try applyLocal(deleteOp)
        try allOps.append(contentsOf: applyLocal(insertOp))
        for rewrite in rewrites {
            try allOps.append(contentsOf: applyLocal(rewrite))
        }
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
}
