//
//  SessionOrigin.swift
//  Woodcase
//

import Foundation

/// Where an edit submitted to a ``DocumentSession`` comes from.
///
/// Every change to a session's document enters through
/// ``DocumentSession/submit(_:)`` as one of these, so there is one funnel for the
/// local author's edits, a file rewritten on disk, a collaborator's CRDT operations,
/// and undo and redo.
///
/// A ``file(_:author:)`` submission needs a session created with a
/// ``DocumentMerger``; a ``remote(_:from:)`` one, a collaborative session.
public enum SessionOrigin: Friendly {
    /// An edit by the session's own author.
    case local(LocalEdit)

    /// The file on disk now holds this document. The author is known when the activity
    /// log explains the write, and `nil` for an outside writer (``Author/external``).
    /// The session merges it three ways with its unwritten local work; local changes
    /// win a same-key conflict, which the change reports.
    case file(PenDocument, author: Author?)

    /// Operations a collaborator broadcast, sent by `from`. Accepted only by a
    /// collaborative session; neither undoable nor dirtying. Each operation is credited
    /// to the author of the replica that made it (see ``DocumentSession/noteJoined(_:)``).
    case remote([CRDTOperation], from: Author)

    /// Undo the local author's most recent undo entry, keeping every other author's
    /// later work. With nothing to undo, it applies nothing.
    case undo

    /// Redo the local author's most recently undone entry, keeping every other author's
    /// later work. With nothing to redo, it applies nothing.
    case redo

    /// The origin's kind, without its payload.
    public var kind: Kind {
        switch self {
        case .local: .local
        case .file: .file
        case .remote: .remote
        case .undo: .undo
        case .redo: .redo
        }
    }

    /// The kinds of origin, as a ``CommittedChange`` reports them.
    public enum Kind: String, Friendly, CaseIterable {
        /// ``SessionOrigin/local(_:)``.
        case local
        /// ``SessionOrigin/file(_:author:)``.
        case file
        /// ``SessionOrigin/remote(_:from:)``.
        case remote
        /// ``SessionOrigin/undo``.
        case undo
        /// ``SessionOrigin/redo``.
        case redo
    }
}
