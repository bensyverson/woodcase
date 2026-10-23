//
//  CRDTSnapshot+Validation.swift
//  Woodcase
//

import Foundation

public extension CRDTSnapshot {
    /// Checks a snapshot another peer sent before a replica adopts it.
    ///
    /// A replica adopting a snapshot witnesses its clock and keeps ticking its vector
    /// clock, so every time in either must be at most ``LamportClock/ceiling``; and the
    /// tree's cycle check walks parent chains, so the tree must have none.
    /// ``CRDTDocument/init(from:peerID:)`` runs this first.
    ///
    /// - Throws: ``RemoteInputError/snapshotTimeOutOfRange(time:)`` or
    ///   ``RemoteInputError/snapshotTreeCycle(nodeID:)``.
    func validate() throws(RemoteInputError) {
        let clockTimes = [operationLog.clock.time] + operationLog.vectorClock.entries.values.sorted()
        if let time = clockTimes.first(where: { $0 > LamportClock.ceiling }) {
            throw .snapshotTimeOutOfRange(time: time)
        }
        if let nodeID = treeMove.firstCycleNode() {
            throw .snapshotTreeCycle(nodeID: nodeID)
        }
    }
}
