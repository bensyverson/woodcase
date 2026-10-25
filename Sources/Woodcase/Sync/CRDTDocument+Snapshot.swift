//
//  CRDTDocument+Snapshot.swift
//  Woodcase
//

import Foundation

public extension CRDTDocument {
    /// Captures the current CRDT state as a serializable snapshot.
    ///
    /// The snapshot contains all state needed for another peer to initialize
    /// a ``CRDTDocument`` without replaying the full operation history.
    ///
    /// - Returns: A ``CRDTSnapshot`` value suitable for encoding and network transfer.
    func snapshot() -> CRDTSnapshot {
        CRDTSnapshot(
            peerID: peerID,
            operationLog: operationLog,
            propertyMaps: propertyMaps,
            childrenLists: childrenLists,
            treeMove: treeMove,
            tombstones: tombstones,
            variableTimestamps: variableTimestamps,
            importTimestamps: importTimestamps,
            themeTimestamps: themeTimestamps,
            documentPropertyTimestamps: documentPropertyTimestamps,
            existenceTimestamps: existenceTimestamps,
            dormantWrites: dormantWrites
        )
    }

    /// Creates a CRDT document from a snapshot, adopting a new peer identity.
    ///
    /// The Lamport clock is advanced past the snapshot's clock to prevent
    /// timestamp collisions between the new peer's operations and those
    /// already in the snapshot.
    ///
    /// The snapshot is checked first (``CRDTSnapshot/validate()``): one from another
    /// peer is untrusted input.
    ///
    /// - Parameters:
    ///   - snapshot: The state to initialize from.
    ///   - peerID: The new peer's unique identifier.
    /// - Throws: The ``RemoteInputError`` that refused the snapshot.
    convenience init(from snapshot: CRDTSnapshot, peerID: PeerID) throws(RemoteInputError) {
        try snapshot.validate()
        // The log is adopted under this replica's id: its operations would otherwise
        // carry the donor's, and collide with the donor's own.
        self.init(peerID: peerID, bootstrapOperationLog: OperationLog(peerID: peerID, adopting: snapshot.operationLog))

        propertyMaps = snapshot.propertyMaps
        childrenLists = snapshot.childrenLists
        treeMove = snapshot.treeMove
        tombstones = snapshot.tombstones
        existenceTimestamps = snapshot.existenceTimestamps
        dormantWrites = snapshot.dormantWrites
        variableTimestamps = snapshot.variableTimestamps
        importTimestamps = snapshot.importTimestamps
        themeTimestamps = snapshot.themeTimestamps
        documentPropertyTimestamps = snapshot.documentPropertyTimestamps

        // Advance clock past the snapshot to prevent timestamp collisions
        operationLog.clock.witness(snapshot.operationLog.clock.time)
    }
}
