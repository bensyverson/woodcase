//
//  DocumentSnapshot.swift
//  Woodcase
//

import Foundation

/// A session's document at one moment, as a value any task can take.
///
/// A ``DocumentSession`` is confined to its owner; its snapshot is not. Hand one to a
/// background task to save, render or export without touching the session, and pass
/// it back to ``DocumentSession/noteSynced(_:)`` once it is written.
public struct DocumentSnapshot: Friendly {
    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - sequence: The sequence of the last change it includes.
    ///   - documentRevision: Its ``EditableDocument/documentRevision``.
    ///   - syncedRevision: The revision of what the file held as far as the session
    ///     knew, or `nil` when it never knew.
    ///   - author: Who edits through the session, or `nil` when unknown.
    public init(
        document: PenDocument,
        sequence: UInt64,
        documentRevision: String,
        syncedRevision: String? = nil,
        author: Author? = nil
    ) {
        self.document = document
        self.sequence = sequence
        self.documentRevision = documentRevision
        self.syncedRevision = syncedRevision
        self.author = author
    }

    /// The document, materialized.
    public var document: PenDocument

    /// The ``CommittedChange/sequence`` of the last change the document includes; 0
    /// before the first.
    public var sequence: UInt64

    /// The document's ``EditableDocument/documentRevision``.
    public var documentRevision: String

    /// The ``EditableDocument/documentRevision`` of what the file held when the snapshot
    /// was taken, as far as the session knew (``DocumentSession/syncedRevision``); `nil`
    /// for a session that never knew. A save checks the file still holds it.
    public var syncedRevision: String?

    /// Who edits through the session the snapshot came from — the identity a save
    /// records its own rows under — or `nil` when unknown.
    public var author: Author?
}
