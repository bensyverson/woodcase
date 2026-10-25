//
//  CRDTStateTransfer.swift
//  Woodcase
//

import Foundation

/// Everything a peer joining a live session needs from a donor, taken at one moment.
///
/// A replica is two things that must agree: the document and the CRDT state that says
/// how it came to be. Hot Swap sends both from the donor, together — the joiner's own
/// file may be older or another file entirely, and a document built from it would
/// disagree with the donor's CRDT state on every node either one changed since.
/// ``EditableDocument/stateTransfer()`` takes one; ``EditableDocument/init(joining:peerID:)``
/// joins from one. It is `Codable` so the app can chunk, seal and send it as it is.
public struct CRDTStateTransfer: Friendly {
    /// The donor's document.
    public var document: PenDocument

    /// The donor's CRDT state, taken with ``document``.
    public var snapshot: CRDTSnapshot

    /// Creates a state transfer.
    ///
    /// - Parameters:
    ///   - document: The donor's document.
    ///   - snapshot: The donor's CRDT state, taken with it.
    public init(document: PenDocument, snapshot: CRDTSnapshot) {
        self.document = document
        self.snapshot = snapshot
    }
}
