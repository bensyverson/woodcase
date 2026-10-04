//
//  DocumentSnapshot.swift
//  Woodcase
//

import Foundation

/// A session's document at one moment, as a value any task can take.
///
/// A ``DocumentSession`` is confined to its owner; its snapshot is not. Hand one to a
/// background task to save, render or export without touching the session, and pass
/// its ``sequence`` back to ``DocumentSession/noteSynced(_:through:)`` once it is
/// written.
public struct DocumentSnapshot: Friendly {
    /// Creates a snapshot.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - sequence: The sequence of the last change it includes.
    ///   - documentRevision: Its ``EditableDocument/documentRevision``.
    public init(document: PenDocument, sequence: UInt64, documentRevision: String) {
        self.document = document
        self.sequence = sequence
        self.documentRevision = documentRevision
    }

    /// The document, materialized.
    public var document: PenDocument

    /// The ``CommittedChange/sequence`` of the last change the document includes; 0
    /// before the first.
    public var sequence: UInt64

    /// The document's ``EditableDocument/documentRevision``.
    public var documentRevision: String
}
