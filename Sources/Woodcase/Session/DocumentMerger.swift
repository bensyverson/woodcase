//
//  DocumentMerger.swift
//  Woodcase
//

import Foundation

/// Folds the file's version of a document into a session's live one.
///
/// A ``DocumentSession`` calls its merger for every ``SessionOrigin/file(_:author:)``
/// submission and applies the operations it returns through its own funnel. The
/// library's merger is ``ThreeWayMerger`` — ``DocumentMerge`` behind this seam — which
/// callers name as `.threeWay`; a test hands the session a stub instead.
///
/// ```swift
/// let session = DocumentSession(document: parsed, author: ben, file: url, merger: .threeWay)
/// let change = try session.submit(.file(onDisk, author: claude))
/// ```
public protocol DocumentMerger {
    /// Merges an external version of a document into the local one.
    ///
    /// Must not change any of the three documents: the session applies the result
    /// itself.
    ///
    /// - Parameters:
    ///   - base: The version both sides started from — what the file last held as far as
    ///     the session knows.
    ///   - ours: The session's live document, which the operations apply to.
    ///   - theirs: The version the file holds now.
    /// - Returns: The operations to apply to `ours` in order, and the conflicts.
    func merge(base: EditableDocument, ours: EditableDocument, theirs: EditableDocument) -> MergeResult
}

public extension DocumentMerger where Self == ThreeWayMerger {
    /// The library's three-way merge: local changes win a same-key conflict, which is
    /// reported.
    static var threeWay: ThreeWayMerger {
        ThreeWayMerger()
    }
}
