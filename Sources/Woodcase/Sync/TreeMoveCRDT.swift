//
//  TreeMoveCRDT.swift
//  Woodcase
//

import Foundation

/// A CRDT for tree-structured move operations, based on Kleppmann et al. 2020.
///
/// Every structural change to the document tree — insert, delete, and move — is
/// modeled as a move operation: `Move(timestamp, nodeID, newParentID)`. Deletion
/// is a move to a special trash sentinel. The algorithm guarantees:
///
/// - **Convergence:** Two replicas that have seen the same set of operations
///   will always agree on the tree structure, regardless of application order.
/// - **Cycle freedom:** Moves that would create a cycle are automatically rejected.
/// - **Out-of-order tolerance:** Late-arriving operations trigger a replay of the
///   move log to produce the correct state.
///
/// ## Algorithm
///
/// Operations are stored in a log sorted by timestamp. When a new operation arrives:
/// 1. If it's the latest, apply directly with a cycle check.
/// 2. If it's out of order, insert it at the correct log position and replay
///    all operations from scratch to rebuild the parent map.
///
/// This ensures convergence because every replica replays the same totally-ordered
/// log and applies the same cycle-rejection rules.
public struct TreeMoveCRDT: Friendly {
    /// A tree move operation.
    public struct MoveOp: Friendly, Comparable {
        /// The operation's timestamp (determines total order).
        public var timestamp: Timestamp
        /// The node being moved.
        public var nodeID: String
        /// The new parent, or `nil` for root.
        public var newParentID: String?

        public init(timestamp: Timestamp, nodeID: String, newParentID: String?) {
            self.timestamp = timestamp
            self.nodeID = nodeID
            self.newParentID = newParentID
        }

        public static func < (lhs: MoveOp, rhs: MoveOp) -> Bool {
            lhs.timestamp < rhs.timestamp
        }
    }

    /// A log entry records the operation and the previous parent for undo.
    struct LogEntry: Friendly {
        var op: MoveOp
        var oldParentID: String??
    }

    /// The current parent for each node. `nil` value = root node.
    public var parentMap: [String: String?]

    /// The sorted log of applied operations.
    private(set) var moveLog: [LogEntry]

    /// The initial parent map used when rebuilding from scratch.
    private var initialParentMap: [String: String?]

    /// Creates a tree move CRDT with an initial parent map.
    ///
    /// - Parameter initialParentMap: The starting parent relationships.
    ///   Keys are node IDs, values are parent IDs (nil = root).
    public init(initialParentMap: [String: String?]) {
        self.initialParentMap = initialParentMap
        parentMap = initialParentMap
        moveLog = []
    }

    /// Applies a move operation, returning whether it was accepted.
    ///
    /// If the operation's timestamp is not the latest, the entire log is
    /// replayed from scratch to ensure correct convergence.
    ///
    /// - Parameter op: The move operation to apply.
    /// - Returns: `true` if the move was applied (no cycle), `false` if rejected.
    @discardableResult
    public mutating func applyMove(_ op: MoveOp) -> Bool {
        // Find correct insertion position in the log
        let insertIdx = moveLog.firstIndex(where: { $0.op.timestamp > op.timestamp }) ?? moveLog.count
        let isLatest = insertIdx == moveLog.count

        if isLatest {
            // Fast path: just check cycle and apply
            if wouldCreateCycle(nodeID: op.nodeID, newParentID: op.newParentID) {
                // Still add to log as rejected (for convergence during rebuild)
                let entry = LogEntry(op: op, oldParentID: parentMap[op.nodeID])
                moveLog.append(entry)
                return false
            }
            let oldParent = parentMap[op.nodeID]
            parentMap[op.nodeID] = op.newParentID
            moveLog.append(LogEntry(op: op, oldParentID: oldParent))
            return true
        } else {
            // Out-of-order: insert into log and rebuild
            let entry = LogEntry(op: op, oldParentID: .none)
            moveLog.insert(entry, at: insertIdx)
            rebuild()
            // Check if the op's effect is present in the rebuilt map
            return parentMap[op.nodeID] == op.newParentID
        }
    }

    /// Checks whether moving `nodeID` under `newParentID` would create a cycle.
    ///
    /// Walks up from `newParentID` to the root. If `nodeID` is found in the
    /// ancestor chain, the move would create a cycle.
    ///
    /// - Parameters:
    ///   - nodeID: The node being moved.
    ///   - newParentID: The proposed new parent (nil = root, never a cycle).
    /// - Returns: `true` if the move would create a cycle.
    public func wouldCreateCycle(nodeID: String, newParentID: String?) -> Bool {
        guard let newParentID else { return false } // move to root never cycles
        if newParentID == nodeID { return true } // self-loop

        var current: String? = newParentID
        while let c = current {
            if let parent = parentMap[c] {
                if let p = parent {
                    if p == nodeID { return true }
                    current = p
                } else {
                    // Parent is root
                    return false
                }
            } else {
                // Node not in parentMap (unknown/root)
                return false
            }
        }
        return false
    }

    /// Replays all operations from scratch to rebuild the parent map.
    ///
    /// This is the core convergence mechanism. By replaying the totally-ordered
    /// log with cycle rejection, all replicas arrive at the same state.
    private mutating func rebuild() {
        parentMap = initialParentMap

        for i in moveLog.indices {
            let op = moveLog[i].op
            moveLog[i].oldParentID = parentMap[op.nodeID]

            if wouldCreateCycle(nodeID: op.nodeID, newParentID: op.newParentID) {
                // Rejected — don't apply, but keep in log
                continue
            }
            parentMap[op.nodeID] = op.newParentID
        }
    }
}
