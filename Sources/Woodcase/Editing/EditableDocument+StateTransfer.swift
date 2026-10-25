//
//  EditableDocument+StateTransfer.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// This replica's document and CRDT state, taken together for a peer joining the
    /// session ("Hot Swap").
    ///
    /// - Returns: The transfer, or `nil` when the document is not collaborative.
    func stateTransfer() -> CRDTStateTransfer? {
        guard let crdtDocument else { return nil }
        return CRDTStateTransfer(document: materialize(), snapshot: crdtDocument.snapshot())
    }

    /// Joins a live session from a donor's ``CRDTStateTransfer``: the flat store is the
    /// donor's document and the CRDT state the donor's, so the two agree.
    ///
    /// The joiner's own file plays no part — it may be older than the session, or another
    /// file. A peer that edited offline replays those operations next, with
    /// ``replayOfflineOperations(_:)``.
    ///
    /// - Parameters:
    ///   - transfer: What the donor sent.
    ///   - peerID: This peer's identifier.
    /// - Throws: The ``RemoteInputError`` that refused the transfer
    ///   (``CRDTStateTransfer/validate()``).
    convenience init(joining transfer: CRDTStateTransfer, peerID: PeerID) throws(RemoteInputError) {
        try transfer.validate()
        self.init(from: transfer.document)
        crdtDocument = try CRDTDocument(from: transfer.snapshot, peerID: peerID)
    }

    /// Replays the operations this peer made while it was offline, after joining from a
    /// donor's state.
    ///
    /// They are taken like any peer's operations (``applyRemote(_:)-([CRDTOperation])``):
    /// those the donor's state already holds are ignored, the rest are applied in causal
    /// order, and any whose causal past the donor's state lacks — an operation from a
    /// third peer this one saw and the donor has not — are held until it arrives, rather
    /// than applied against a list position or node this replica does not have. Once
    /// applied they are in this replica's log, so ``pendingOperations(since:)`` sends
    /// them on.
    ///
    /// Replay every offline operation, in one call, before making a local edit: a local
    /// edit made while some are held depends on them, so peers keep this replica's order,
    /// but one replayed *after* a local edit would be taken for a duplicate.
    ///
    /// - Parameter operations: The offline operations, from this peer's earlier log.
    /// - Returns: The operations refused at the boundary, as ``applyRemote(_:)-([CRDTOperation])``
    ///   returns them.
    @discardableResult
    func replayOfflineOperations(_ operations: [CRDTOperation]) -> [RemoteInputError] {
        applyRemote(operations)
    }
}
