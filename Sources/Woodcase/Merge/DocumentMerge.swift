//
//  DocumentMerge.swift
//  Woodcase
//

import Foundation

/// Folds an external version of a document into the local one, as edit operations.
///
/// Given the version both sides started from, a three-way merge takes every change
/// the external side made and keeps every change the local side made; where both
/// changed the same thing differently, the local change wins and the merge says so in
/// a ``MergeConflict``. The result is a list of ordinary ``EditOperation``s to apply
/// to the local document in order, so a merge is undoable, attributable and visible
/// to everything that already watches operations.
///
/// ```swift
/// let result = DocumentMerge.merge(base: lastWritten, ours: local, theirs: onDisk)
/// for conflict in result.conflicts {
///     print(conflict.subject, conflict.kind)
/// }
/// ```
///
/// An editor applies `result.operations` through its ``DocumentSession`` so the merge
/// lands in the ledger and the activity log like any other change, never by calling
/// ``EditableDocument/apply(_:)`` itself.
///
/// Nodes are matched by id: a writer that mints new ids wholesale reads as a delete of
/// every old node and an insert of every new one. Unchanged subtrees are recognized by
/// ``EditableDocument/revision(of:)`` and never walked, so merging a small edit into a
/// large document costs little; equal 64-bit revisions are trusted.
///
/// The rules are in `project/2026-10-04-three-way-diff-design.md` and in
/// <doc:EditingDocuments> under "Merging Documents".
public enum DocumentMerge {
    /// Merges an external version of a document into the local one.
    ///
    /// Pure and synchronous: none of the three documents is changed. The inputs'
    /// revision caches are read, and warmed.
    ///
    /// - Parameters:
    ///   - base: The version both sides started from — what the local side last read
    ///     or wrote.
    ///   - ours: The local document, which the operations apply to.
    ///   - theirs: The external version being folded in.
    /// - Returns: The operations, the conflicts, and whether local work survived.
    public static func merge(base: EditableDocument, ours: EditableDocument, theirs: EditableDocument) -> MergeResult {
        var resolver = ThreeWayResolver(base: base, ours: ours, theirs: theirs)
        let resolution = resolver.run()
        var sequencer = OpSequencer(resolution: resolution, ours: ours, theirs: theirs)
        return MergeResult(
            operations: sequencer.run(),
            conflicts: resolution.conflicts,
            keepsLocalChanges: !resolution.reachesTheirs(ours: ours, theirs: theirs)
        )
    }

    /// The operations that turn one document into another: a merge in which the local
    /// side changed nothing.
    ///
    /// - Parameters:
    ///   - from: The document the operations apply to.
    ///   - to: The document they produce.
    /// - Returns: The operations, to apply to `from` in order.
    public static func diff(from: EditableDocument, to: EditableDocument) -> [EditOperation] {
        merge(base: from, ours: from, theirs: to).operations
    }
}
