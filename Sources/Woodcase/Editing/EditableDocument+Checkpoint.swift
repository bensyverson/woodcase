//
//  EditableDocument+Checkpoint.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Returns the current vector clock for broadcasting as a checkpoint.
    ///
    /// The consuming app broadcasts this clock to other peers. When all peers'
    /// checkpoints are collected, pass them to ``VectorClock/minimum(of:)`` to
    /// compute the consensus clock, then call ``truncateLog(acknowledgedBy:)``
    /// to reclaim memory.
    ///
    /// - Returns: The current vector clock, or an empty clock if not in collaborative mode.
    func checkpoint() -> VectorClock {
        guard let crdtDocument else { return VectorClock() }
        return crdtDocument.operationLog.vectorClock
    }

    /// Truncates the operation log, removing operations acknowledged by all peers.
    ///
    /// Call this after computing a consensus clock via ``VectorClock/minimum(of:)``
    /// from all peers' checkpoint clocks. Operations whose timestamps are dominated
    /// by the consensus clock are safe to discard.
    ///
    /// - Parameter consensusClock: The component-wise minimum of all peers' clocks.
    func truncateLog(acknowledgedBy consensusClock: VectorClock) {
        crdtDocument?.operationLog.truncate(acknowledgedBy: consensusClock)
    }
}
