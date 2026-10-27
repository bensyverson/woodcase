//
//  EditableDocument+Collaborative.swift
//  Woodcase
//

import Foundation

public extension EditableDocument {
    /// Turns on collaborative mode in place: seeds a ``CRDTDocument`` from the document
    /// as it is now, as ``init(from:peerID:)`` does from a parsed one. Its
    /// ``seedFingerprint`` is that of the current document. A document that is already
    /// collaborative keeps its CRDT.
    ///
    /// - Parameter peerID: This peer's identifier for the collaborative session.
    func makeCollaborative(peerID: PeerID) {
        guard crdtDocument == nil else { return }
        crdtDocument = CRDTDocument(peerID: peerID, document: self)
    }
}
