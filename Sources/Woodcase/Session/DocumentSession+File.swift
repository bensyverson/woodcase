//
//  DocumentSession+File.swift
//  Woodcase
//

import Foundation

extension DocumentSession {
    /// Folds the document the file now holds into the live one.
    ///
    /// The session's ``merger`` diffs three ways — the base is the document as the file
    /// was last known to hold it, ours the live document, theirs the file's — and
    /// returns operations that take every external change while keeping every unwritten
    /// local one; where both changed the same key, the local value wins and the conflict
    /// is reported (ruling 3 in the session design). The operations then go through the
    /// same path as a local edit — normalized, keyed, given guarded inverses, through
    /// the CRDT in collaborative mode, so collaborators who cannot see the file receive
    /// them — but under the file's writer:
    ///
    /// - the ledger stamps every key the merge wrote with the writer, so the local
    ///   author's undo keeps it;
    /// - nothing joins the undo history, and redo and the open undo group are left alone;
    /// - no activity is written — whoever wrote the file logged it;
    /// - the file's document becomes the merge base, and the session is in sync with its
    ///   file unless local work survived the merge (``MergeResult/keepsLocalChanges``).
    ///
    /// Like a local edit, the merge lands whole or not at all: if an operation fails,
    /// the ones before it are taken back, the base does not move, and the error is
    /// rethrown.
    ///
    /// - Parameters:
    ///   - written: The document the file holds now.
    ///   - writer: Who wrote it, when the activity log says; `nil` credits
    ///     ``Author/external``.
    /// - Returns: The committed change, its ``CommittedChange/conflicts`` copied from the
    ///   merge. With nothing to apply, a change that keeps the current sequence.
    /// - Throws: ``SessionError/mergeUnavailable`` for a session without a merger,
    ///   ``SessionError/fileStateUnknown`` for one that never knew its file's contents,
    ///   or the ``EditingError`` of the operation that failed.
    func commitFile(_ written: PenDocument, author writer: Author?) throws -> CommittedChange {
        guard let merger else { throw SessionError.mergeUnavailable }
        guard let base else { throw SessionError.fileStateUnknown }
        let writer = writer ?? .external
        let theirs = EditableDocument(from: written)
        let result = merger.merge(base: base, ours: document, theirs: theirs)

        let change: CommittedChange
        if result.operations.isEmpty {
            var empty = emptyChange(origin: .file)
            empty.author = writer
            empty.conflicts = result.conflicts
            change = empty
        } else {
            change = try applyMerge(result, by: writer)
        }

        mergeBase = .built(theirs)
        if result.keepsLocalChanges {
            fileDiffersFromDocument = true
        } else {
            syncedSequence = sequence
            fileDiffersFromDocument = false
        }
        return change
    }

    /// Applies a merge's operations under the file's writer, all of them or none.
    ///
    /// - Parameters:
    ///   - result: The merge.
    ///   - writer: Who wrote the file.
    /// - Returns: The committed change.
    /// - Throws: The ``EditingError`` of the operation that failed, after taking back
    ///   the ones before it.
    private func applyMerge(_ result: MergeResult, by writer: Author) throws -> CommittedChange {
        let crdtBefore = result.operations.count > 1 ? document.crdtDocument?.snapshot() : nil
        var pending = PendingChange(logsActivity: false)
        do {
            for operation in result.operations {
                try apply(operation, into: &pending)
            }
        } catch {
            abandon(pending, restoring: crdtBefore)
            throw error
        }
        return commit(
            pending,
            origin: .file,
            isUndoable: false,
            by: writer,
            isDirtying: result.keepsLocalChanges,
            conflicts: result.conflicts
        )
    }
}
