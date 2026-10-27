//
//  DocumentSession+Joining.swift
//  Woodcase
//

import Foundation

public extension DocumentSession {
    /// Creates a collaborative session that joins a live one from a donor's
    /// ``CRDTStateTransfer`` ("Hot Swap").
    ///
    /// The session's document is the donor's, with the donor's CRDT state under
    /// `author`'s peer id, so it reports the donor's
    /// ``EditableDocument/seedFingerprint`` and takes the donor's later operations as
    /// ``SessionOrigin/remote(_:from:)``. An app replaces its window's session with this
    /// one once a full state transfer arrives; the old session's undo history and ledger
    /// describe a board the window no longer shows, so nothing carries over. A peer that
    /// edited offline replays those operations next, through
    /// ``EditableDocument/replayOfflineOperations(_:)`` on ``document``.
    ///
    /// The session counts as unsynced from the start: its file, if any, never held the
    /// donor's board.
    ///
    /// - Parameters:
    ///   - transfer: What the donor sent.
    ///   - author: Who edits through this session; its peer id signs the session's
    ///     operations.
    ///   - file: The .pen file or `.umbra` bundle the session saves to, or `nil` for one
    ///     never saved.
    ///   - synced: The document the file holds, as last read — the base a later
    ///     ``SessionOrigin/file(_:author:)`` submission merges from — or `nil` when there
    ///     is no file state to merge against.
    ///   - merger: What folds a file's document in, or `nil` to refuse file submissions.
    /// - Throws: The ``RemoteInputError`` that refused the transfer
    ///   (``CRDTStateTransfer/validate()``).
    convenience init(
        joining transfer: CRDTStateTransfer,
        author: Author,
        file: URL? = nil,
        synced: PenDocument? = nil,
        merger: (any DocumentMerger)? = nil
    ) throws(RemoteInputError) {
        let document = try EditableDocument(joining: transfer, peerID: author.peerID)
        self.init(editing: document, author: author, file: file, synced: synced, merger: merger)
        fileDiffersFromDocument = true
    }
}
