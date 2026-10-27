//
//  DocumentSession+ReversalScope.swift
//  Woodcase
//

import Foundation

extension DocumentSession {
    /// The nodes the steps of one reversal put back and take away before a later step
    /// of it runs, so that step's guard is weighed against the document it will meet.
    ///
    /// A reversal that rebuilds structure is checked whole before any step runs, but its
    /// steps depend on each other: undoing a detach removes the copy, re-inserts the ref,
    /// then restores the connector ends — guarded by keys that name the ref. Checked
    /// against the document before the reversal, the ref is missing and the undo would
    /// be skipped. Only existence is simulated; other authors' writes are still read
    /// from the ledger, so no guard is weakened.
    struct ReversalScope: Friendly {
        /// Ids an earlier step inserts.
        var recreated: Set<String> = []

        /// Ids an earlier step deletes.
        var removed: Set<String> = []

        /// Whether a node a step needs is gone: absent from the document and not put
        /// back by an earlier step. A node an earlier step removes is the reversal's own
        /// doing, not a missing node, and is not counted.
        ///
        /// - Parameters:
        ///   - id: The node.
        ///   - document: The document as it stands before the reversal.
        /// - Returns: Whether the node is missing.
        func isMissing(_ id: String, in document: EditableDocument) -> Bool {
            document.nodes[id] == nil && !recreated.contains(id)
        }

        /// Whether an id a step would insert is in use when it runs.
        ///
        /// - Parameters:
        ///   - id: The id.
        ///   - document: The document as it stands before the reversal.
        /// - Returns: Whether the id is taken.
        func isTaken(_ id: String, in document: EditableDocument) -> Bool {
            recreated.contains(id) || (document.nodes[id] != nil && !removed.contains(id))
        }

        /// Records what one step adds and removes.
        ///
        /// - Parameters:
        ///   - operation: The step's operation.
        ///   - document: The document as it stands before the reversal.
        mutating func advance(past operation: EditOperation, in document: EditableDocument) {
            switch operation {
            case let .insertNode(op):
                let ids = document.collectInsertedIDs(in: op.node)
                recreated.formUnion(ids)
                removed.subtract(ids)
            case let .deleteNode(op):
                let ids = document.nodes[op.nodeID] == nil ? [op.nodeID] : document.descendantIDs(of: op.nodeID)
                removed.formUnion(ids)
                recreated.subtract(ids)
            default:
                break
            }
        }
    }
}
