//
//  DocumentSession+Collaborative.swift
//  Woodcase
//

import Foundation

public extension DocumentSession {
    /// Makes the session collaborative in place, as an app does when its user starts
    /// sharing: the document gains a ``CRDTDocument`` seeded from what it holds now,
    /// under ``author``'s peer id (``EditableDocument/makeCollaborative(peerID:)``).
    ///
    /// The session stays the same session — its undo and redo stacks, ledger, sequence
    /// and merge base are untouched — so undo still undoes what its author did, and from
    /// now on every local change, an undo of an earlier edit included, comes back with
    /// operations to broadcast. Peers join from ``EditableDocument/stateTransfer()``
    /// taken after this call. A session that is already collaborative is left as it is.
    func makeCollaborative() {
        document.makeCollaborative(peerID: author.peerID)
    }
}
