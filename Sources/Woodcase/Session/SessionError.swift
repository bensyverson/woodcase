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
    /// The session cannot take edits from this kind of origin yet.
    case unsupportedOrigin(SessionOrigin.Kind)
    /// The session keeps no CRDT, so it cannot take a collaborator's operations: create it
    /// with `collaborative: true`.
    case notCollaborative
}

extension SessionError: LocalizedError {
    /// A sentence saying what was refused.
    public var errorDescription: String? {
        switch self {
        case let .unsupportedOrigin(kind):
            "A document session cannot apply \(kind.rawValue) changes yet."
        case .notCollaborative:
            "A document session that is not collaborative cannot apply remote operations."
        }
    }
}
