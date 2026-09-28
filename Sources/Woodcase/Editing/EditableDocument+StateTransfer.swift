//
//  EditableDocument+StateTransfer.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Creates an editable document by merging a local .pen file with a remote CRDT snapshot.
    ///
    /// This is the "Hot Swap" entry point: a peer joining a live session flattens
    /// their local `.pen` file for the document structure (nodes, version, themes,
    /// imports, variables), then attaches a ``CRDTDocument`` initialized from the
    /// remote snapshot for convergence state.
    ///
    /// - Parameters:
    ///   - document: The local .pen document to flatten.
    ///   - snapshot: The remote peer's CRDT state snapshot.
    ///   - peerID: This peer's unique identifier.
    convenience init(from document: PenDocument, snapshot: CRDTSnapshot, peerID: PeerID) {
        self.init(from: document)
        crdtDocument = CRDTDocument(from: snapshot, peerID: peerID)
    }

    /// Replays offline operations against the current CRDT state.
    ///
    /// After initializing from a snapshot, a peer may have locally-generated
    /// operations from their offline session that need to be merged. These are
    /// applied as remote operations (since the CRDT document was freshly
    /// initialized from the remote snapshot, not from the local session).
    ///
    /// - Parameter operations: The offline operations to replay.
    func replayOfflineOperations(_ operations: [CRDTOperation]) {
        applyRemote(operations)
    }
}
