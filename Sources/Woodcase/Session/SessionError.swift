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
}

extension SessionError: LocalizedError {
    /// A sentence saying what was refused.
    public var errorDescription: String? {
        switch self {
        case let .unsupportedOrigin(kind):
            "A document session cannot apply \(kind.rawValue) changes yet."
        }
    }
}
