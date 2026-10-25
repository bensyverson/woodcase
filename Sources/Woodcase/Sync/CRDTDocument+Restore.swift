//
//  CRDTDocument+Restore.swift
//  Woodcase
//

import Foundation

extension CRDTDocument {
    /// Puts the CRDT state back exactly as a snapshot of this same document captured it.
    ///
    /// Unlike ``init(from:peerID:)``, the clock is restored as captured rather than
    /// advanced: this is for taking back operations that never left the replica — a
    /// local edit refused part-way — so to every peer they never happened. Restoring
    /// past an operation that was sent would reuse its timestamps.
    ///
    /// - Parameter snapshot: A snapshot this document took, with no operation sent
    ///   since.
    func restore(_ snapshot: CRDTSnapshot) {
        precondition(snapshot.peerID == peerID, "A CRDT document can only restore its own snapshot")
        operationLog = snapshot.operationLog
        propertyMaps = snapshot.propertyMaps
        childrenLists = snapshot.childrenLists
        treeMove = snapshot.treeMove
        tombstones = snapshot.tombstones
        variableTimestamps = snapshot.variableTimestamps
        importTimestamps = snapshot.importTimestamps
        themeTimestamps = snapshot.themeTimestamps
        documentPropertyTimestamps = snapshot.documentPropertyTimestamps
    }
}
