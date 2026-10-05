//
//  SessionError.swift
//  Woodcase
//

import Foundation

/// Why a ``DocumentSession`` refused a submission before touching the document.
///
/// Errors from the edit itself — a missing node, a stale revision — are the
/// ``EditingError`` the document raised, passed through unchanged.
public enum SessionError: Error, Friendly {
    /// The session keeps no CRDT, so it cannot take a collaborator's operations: create it
    /// with `collaborative: true`.
    case notCollaborative
    /// A remote change landed after the checkpoint, so rolling back would restore a
    /// ledger without that change's stamps while its effects stay in the document — and a
    /// later undo could then overwrite it. Nothing was rolled back.
    case rollbackAcrossRemoteChange
    /// The session was created without a ``DocumentMerger``, so it cannot fold a file's
    /// document into its own. Nothing was applied.
    case mergeUnavailable
    /// The session was never told what its file holds — it wraps a document with no
    /// file state — so a file merge has no base to diff from, and a save cannot check
    /// that the file still holds what the session last read. Nothing was applied or
    /// written.
    case fileStateUnknown
}

extension SessionError: LocalizedError {
    /// A sentence saying what was refused.
    public var errorDescription: String? {
        switch self {
        case .notCollaborative:
            "A document session that is not collaborative cannot apply remote operations."
        case .rollbackAcrossRemoteChange:
            "A document session cannot roll back past a collaborator's change."
        case .mergeUnavailable:
            "A document session without a merger cannot apply changes from its file."
        case .fileStateUnknown:
            "A document session that never knew its file's contents cannot merge with or save to it."
        }
    }
}
