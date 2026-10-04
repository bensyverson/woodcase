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
        guard !edit.operations.isEmpty else { return emptyChange() }

        let batch = UUID().uuidString
        let crdtBefore = edit.operations.count > 1 ? document.crdtDocument?.snapshot() : nil
        var applied: [AppliedOperation] = []
        var broadcast: [CRDTOperation] = []
        var keys: [ChangeKey] = []
        var invalidation = ChangeInvalidation()
        var activity: [ActivityEvent] = []
        do {
            for operation in edit.operations {
                let forward = operation.normalized(in: document)
                let operationKeys = try ChangeKey.keys(of: forward, in: document)
                let inverse = try document.granularInverse(of: forward)
                let probe = ChangeInvalidation.Probe(operation: forward, keys: operationKeys, in: document)
                let touched = ActivityEvent.nodeIDs(touchedBy: forward)
                let pathsBefore = touched.map(document.namePath(of:))

                broadcast += try applyThroughCRDT(forward)

                applied.append(AppliedOperation(forward: forward, inverse: inverse))
                keys += operationKeys
                invalidation.formUnion(probe.invalidation(after: document))
                if let event = activityEvent(
                    for: forward,
                    inverse: inverse,
                    kind: edit.activityKind,
                    nodes: touched,
                    pathsBefore: pathsBefore,
                    batch: batch
                ) {
                    activity.append(event)
                }
            }
        } catch {
            if let crdtBefore, let crdt = document.crdtDocument {
                unwindFlatStore(applied)
                crdt.restore(crdtBefore)
            } else {
                unwind(applied)
            }
            throw error
        }

        sequence += 1
        lastDirtyingSequence = sequence
        ledger.stamp(keys, by: author, at: sequence)
        return CommittedChange(
            origin: .local,
            author: author,
            applied: applied,
            invalidation: invalidation,
            sequence: sequence,
            documentRevision: document.documentRevision,
            activity: activity,
            broadcast: broadcast,
            isUndoable: edit.undoGroup != .none,
            isDirtying: true
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

    /// The activity event for one applied operation, or `nil` for a session with no
    /// file to attribute it to.
    ///
    /// Each name path is read from whichever side of the edit still has its node: after
    /// it for a node that survived, before it for one the operation removed.
    private func activityEvent(
        for operation: EditOperation,
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
            revision: document.documentRevision,
            batch: batch
        )
    }

    /// A change that applied nothing: it keeps the current sequence and dirties nothing.
    private func emptyChange() -> CommittedChange {
        CommittedChange(
            origin: .local,
            author: author,
            applied: [],
            invalidation: ChangeInvalidation(),
            sequence: sequence,
            documentRevision: document.documentRevision,
            isUndoable: false,
            isDirtying: false
        )
    }
}
