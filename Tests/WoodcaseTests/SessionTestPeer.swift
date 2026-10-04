//
//  SessionTestPeer.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Another replica of a collaborative session's document, editing as another author:
/// what a collaborator's window would broadcast, for the session to take as
/// ``SessionOrigin/remote(_:from:)``.
final class SessionTestPeer {
    /// Creates a replica of a document under an author's peer id.
    ///
    /// - Parameters:
    ///   - author: Who edits on this replica.
    ///   - document: The document both replicas start from.
    init(_ author: Author, document: PenDocument) {
        self.author = author
        replica = EditableDocument(from: document, peerID: author.peerID)
    }

    /// Who edits on this replica.
    let author: Author

    /// The replica's document.
    let replica: EditableDocument

    /// Takes in what a session broadcast, so the replica has seen it before it edits.
    ///
    /// - Parameter change: The session's change.
    func receive(_ change: CommittedChange) {
        replica.applyRemote(change.broadcast)
    }

    /// Edits the replica and returns the operations it broadcasts.
    ///
    /// - Parameter operation: The edit.
    /// - Returns: The CRDT operations to deliver to the session.
    func edit(_ operation: EditOperation) throws -> [CRDTOperation] {
        try replica.applyLocal(operation)
    }
}
