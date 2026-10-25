//
//  CRDTDocument+CausalDelivery.swift
//  Woodcase
//

import Foundation

/// Causal delivery: remote operations are applied in an order that respects what each
/// one depended on, whatever order they arrive in, and each exactly once.
///
/// A relay delivers late, out of order and more than once — a retry, a replay after a
/// reconnect, a Hot Swap whose snapshot already holds some of what follows. The CRDT's
/// merges are only order-free for operations whose causal past has been applied: a write
/// to a node that has not been created yet, or an insert after a list position that has
/// not arrived, would be dropped or misplaced on one replica and not another. So an
/// operation is *held* until every operation its ``CRDTOperation/dependencies`` names
/// has been applied here, and one this replica already has is ignored.
///
/// The vector clock is the record of what has been applied: its entry for a peer is the
/// Lamport time of that peer's latest applied operation, and because each peer's
/// operations are applied in causal order, every earlier one of that peer's has been
/// applied too. So an operation is a duplicate exactly when the clock already
/// ``VectorClock/covers(_:)`` its id, and ready exactly when the clock
/// ``VectorClock/dominates(_:)`` its dependencies.
extension CRDTDocument {
    /// The remote operations received but not yet applied, because part of their causal
    /// past has not arrived; in id order.
    public var heldOperations: [CRDTOperation] {
        held.values.sorted { $0.id < $1.id }
    }

    /// Takes a validated remote operation into the hold, unless this replica has it.
    ///
    /// The Lamport clock witnesses it at once, so no local operation made while it is
    /// held can take its id.
    ///
    /// - Parameter operation: The operation, already through ``validateRemote(_:)``.
    /// - Returns: `false` when it was a duplicate — applied already, or already held.
    @discardableResult
    func hold(_ operation: CRDTOperation) -> Bool {
        guard !operationLog.vectorClock.covers(operation.id), held[operation.id] == nil else { return false }
        operationLog.clock.witness(operation.id.time)
        held[operation.id] = operation
        return true
    }

    /// Removes and returns the held operation to apply next: of those whose causal past
    /// has been applied, the one with the smallest id. `nil` when none is ready.
    func nextDeliverable() -> CRDTOperation? {
        let clock = operationLog.vectorClock
        guard let next = held.values
            .filter({ clock.dominates($0.dependencies) })
            .min(by: { $0.id < $1.id })
        else { return nil }
        held[next.id] = nil
        return next
    }

    /// The latest of this replica's own operations that is held: one it made on an
    /// earlier run, being replayed. A local operation made now depends on it, so every
    /// peer applies this replica's operations in the order it made them.
    var latestHeldOwnTime: UInt64? {
        held.keys.filter { $0.peerID == peerID }.map(\.time).max()
    }
}
