//
//  DocumentSession+MergeBase.swift
//  Woodcase
//

import Foundation

extension DocumentSession {
    /// The document as the file was last known to hold it, in whichever form the session
    /// has it.
    ///
    /// Building an ``EditableDocument`` flattens a whole document, which only a file
    /// merge needs; a one-shot CLI session never merges. So the session keeps the
    /// written document as a value and builds the editable base on first use.
    ///
    /// Not `Friendly`: it holds an ``EditableDocument``, a reference type that is neither
    /// `Codable` nor `Sendable`, and it never leaves the session.
    enum MergeBase {
        /// The file's document, not yet built into an editable base.
        case deferred(PenDocument)
        /// The editable base, built and kept so its revision cache stays warm between
        /// merges.
        case built(EditableDocument)
        /// The session was never told what the file holds: it wraps a document with no
        /// file state, so there is nothing to merge against.
        case unknown
    }

    /// The document as the file was last known to hold it — the base of a file merge —
    /// built on first use; `nil` when the session was never told what the file holds.
    var base: EditableDocument? {
        switch mergeBase {
        case let .built(base):
            return base
        case let .deferred(written):
            let base = EditableDocument(from: written)
            mergeBase = .built(base)
            return base
        case .unknown:
            return nil
        }
    }

    /// Whether the editable merge base has been built.
    var hasBuiltBase: Bool {
        if case .built = mergeBase { return true }
        return false
    }
}
