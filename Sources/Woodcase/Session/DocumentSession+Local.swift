//
//  DocumentSession+Local.swift
//  Woodcase
//

import Foundation

extension DocumentSession {
    /// Applies the author's own edit, all of it or none of it.
    ///
    /// Each operation is normalized, keyed and given its granular inverse against the
    /// document as it stands, then applied — through the CRDT in collaborative mode.
    /// If one fails, the ones already applied are undone in reverse before the error is
    /// rethrown, and nothing is stamped, journaled or numbered.
    ///
    /// In collaborative mode the CRDT must forget the refused edit too: its operations
    /// were never broadcast, so unwinding through the CRDT would log forward and
    /// compensating operations no peer receives, leaving gaps in this replica's clock
    /// and letting a concurrent remote write land on different sides of them here and
    /// there. So a multi-operation edit captures the CRDT state first and, on failure,
    /// unwinds the flat store alone and restores that state. A single operation needs
    /// no capture: ``EditableDocument/applyLocal(_:)`` refuses before the CRDT sees it.
    ///
    /// - Parameter edit: The edit.
    /// - Returns: The committed change.
    /// - Throws: The ``EditingError`` of the revision check or of the operation that
    ///   failed.
    func commitLocal(_ edit: LocalEdit) throws -> CommittedChange {
        try checkExpectedRevisions(edit.expecting)
        guard !edit.operations.isEmpty else { return emptyChange(origin: .local) }

        let crdtBefore = edit.operations.count > 1 ? document.crdtDocument?.snapshot() : nil
        var pending = pendingChange(activityKind: edit.activityKind)
        do {
            for operation in edit.operations {
                try apply(operation, into: &pending)
            }
        } catch {
            abandon(pending, restoring: crdtBefore)
            throw error
        }

        let change = commit(pending, origin: .local, isUndoable: edit.undoGroup != .none)
        history.record(UndoEntry(undoing: change.applied, at: change.sequence), group: edit.undoGroup)
        return change
    }

    /// Applies one operation as part of a change, recording what it did.
    ///
    /// The operation is normalized, keyed and given its granular inverse against the
    /// document as it stands, then applied — through the CRDT in collaborative mode.
    ///
    /// - Parameters:
    ///   - operation: The operation.
    ///   - pending: The change it is part of.
    /// - Throws: The ``EditingError`` that refused the operation, before any write.
    func apply(_ operation: EditOperation, into pending: inout PendingChange) throws {
        let forward = operation.normalized(in: document)
        let operationKeys = try ChangeKey.keys(of: forward, in: document)
        let inverse = try document.granularInverse(of: forward)
        let probe = ChangeInvalidation.Probe(operation: forward, keys: operationKeys, in: document)
        let touched = ActivityEvent.nodeIDs(touchedBy: forward)
        let pathsBefore = touched.map(document.namePath(of:))

        pending.broadcast += try applyThroughCRDT(forward)

        pending.applied.append(AppliedOperation(forward: forward, inverse: inverse))
        pending.keys += operationKeys
        pending.invalidation.formUnion(probe.invalidation(after: document))
        if let event = activityEvent(
            for: forward,
            as: operation,
            inverse: inverse,
            kind: pending.activityKind,
            nodes: touched,
            pathsBefore: pathsBefore,
            batch: pending.batch
        ) {
            pending.activity.append(event)
        }
    }

    /// Takes back a change that failed part-way, leaving the session as it was.
    ///
    /// - Parameters:
    ///   - pending: The change, as far as it got.
    ///   - crdtBefore: The CRDT state captured before the change, to restore instead of
    ///     unwinding through the CRDT; `nil` to unwind through the same path that
    ///     applied the operations.
    func abandon(_ pending: PendingChange, restoring crdtBefore: CRDTSnapshot?) {
        if let crdtBefore, let crdt = document.crdtDocument {
            unwindFlatStore(pending.applied)
            crdt.restore(crdtBefore)
        } else {
            unwind(pending.applied)
        }
    }

    /// Numbers, stamps and describes a change that applied in full.
    ///
    /// - Parameters:
    ///   - pending: The change.
    ///   - origin: Where it came from.
    ///   - isUndoable: Whether it joined the author's undo history.
    ///   - kept: Other authors' work an undo or redo left in place.
    /// - Returns: The committed change.
    func commit(
        _ pending: PendingChange,
        origin: SessionOrigin.Kind,
        isUndoable: Bool,
        kept: [KeptChange] = []
    ) -> CommittedChange {
        sequence += 1
        lastDirtyingSequence = sequence
        ledger.stamp(pending.keys, by: author, at: sequence)
        return CommittedChange(
            origin: origin,
            author: author,
            applied: pending.applied,
            invalidation: pending.invalidation,
            sequence: sequence,
            documentRevision: document.documentRevision,
            activity: pending.activity,
            broadcast: pending.broadcast,
            isUndoable: isUndoable,
            isDirtying: true,
            kept: kept
        )
    }

    /// Applies one operation to the document, through its CRDT when there is one.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The CRDT operations to broadcast; empty outside collaborative mode.
    /// - Throws: The ``EditingError`` that refused the operation, before any write.
    func applyThroughCRDT(_ operation: EditOperation) throws -> [CRDTOperation] {
        if document.crdtDocument != nil {
            return try document.applyLocal(operation)
        }
        try document.apply(operation)
        return []
    }

    /// Takes back applied operations, newest first, through the same path that applied
    /// them.
    ///
    /// Each inverse was captured before its operation and is exact against the state
    /// that operation left, so an inverse that fails here is a bug in the inverse, not a
    /// condition to recover from; the rest still run, to get as close as possible.
    ///
    /// - Parameter applied: The operations to take back, in the order they were applied.
    /// - Returns: The CRDT operations the unwind generated, which collaborators need to
    ///   converge on the restored state.
    @discardableResult
    func unwind(_ applied: [AppliedOperation]) -> [CRDTOperation] {
        var broadcast: [CRDTOperation] = []
        for operation in applied.reversed() {
            for step in operation.inverse {
                if let ops = try? applyThroughCRDT(step.resolved(in: document)) {
                    broadcast += ops
                }
            }
        }
        return broadcast
    }

    /// Takes back applied operations, newest first, in the flat store alone, leaving the
    /// CRDT state for the caller to restore.
    ///
    /// - Parameter applied: The operations to take back, in the order they were applied.
    private func unwindFlatStore(_ applied: [AppliedOperation]) {
        for operation in applied.reversed() {
            for step in operation.inverse {
                try? document.apply(step.resolved(in: document))
            }
        }
    }

    /// Refuses an edit whose author saw a different version of a node than the
    /// document now holds.
    private func checkExpectedRevisions(_ expecting: [String: String]) throws {
        for (nodeID, expected) in expecting.sorted(by: { $0.key < $1.key }) {
            guard let actual = document.revision(of: nodeID) else {
                throw EditingError.nodeNotFound(id: nodeID)
            }
            guard actual == expected else {
                throw EditingError.revisionConflict(nodeID: nodeID, expected: expected, actual: actual)
            }
        }
    }

    /// A change about to be built, its activity events sharing the session's batch id
    /// when it has one.
    ///
    /// - Parameter activityKind: The verb every event is labeled with, or `nil` to label
    ///   each by its operation.
    /// - Returns: The empty change.
    func pendingChange(activityKind: ActivityEvent.Kind?) -> PendingChange {
        PendingChange(batch: activityBatch ?? UUID().uuidString, activityKind: activityKind)
    }

    /// The activity event for one applied operation, or `nil` for a session with no
    /// file to attribute it to.
    ///
    /// Each name path is read from whichever side of the edit still has its node: after
    /// it for a node that survived, before it for one the operation removed. The row's
    /// `forward` is the operation as submitted, not normalized, so a reader sees what
    /// the writer asked for.
    private func activityEvent(
        for operation: EditOperation,
        as submitted: EditOperation,
        inverse: [GuardedInverse],
        kind: ActivityEvent.Kind?,
        nodes: [String],
        pathsBefore: [String],
        batch: String
    ) -> ActivityEvent? {
        guard let file else { return nil }
        let paths = zip(nodes, pathsBefore).map { nodeID, before in
            document.nodes[nodeID] == nil ? before : document.namePath(of: nodeID)
        }
        return ActivityEvent(
            time: Date(),
            identity: author.name,
            file: file,
            op: kind ?? ActivityEvent.Kind(operation),
            nodes: nodes,
            paths: paths,
            inverse: inverse.map(\.operation),
            forward: [submitted],
            revision: document.documentRevision,
            batch: batch
        )
    }

    /// A change that applied nothing: it keeps the current sequence and dirties nothing.
    ///
    /// - Parameters:
    ///   - origin: Where the change came from.
    ///   - kept: Other authors' work an undo or redo left in place instead.
    /// - Returns: The change.
    func emptyChange(origin: SessionOrigin.Kind, kept: [KeptChange] = []) -> CommittedChange {
        CommittedChange(
            origin: origin,
            author: author,
            applied: [],
            invalidation: ChangeInvalidation(),
            sequence: sequence,
            documentRevision: document.documentRevision,
            isUndoable: false,
            isDirtying: false,
            kept: kept
        )
    }
}
