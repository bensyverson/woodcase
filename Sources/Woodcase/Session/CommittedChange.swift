//
//  CommittedChange.swift
//  Woodcase
//

import Foundation

/// Everything one submission to a ``DocumentSession`` did, as one value.
///
/// The owner of a session reacts to its edits through this and nothing else: it
/// re-derives what ``invalidation`` names, appends ``activity`` to the log, sends
/// ``broadcast`` to collaborators, marks the document edited when ``isDirtying``, and
/// tells the author about anything an undo ``kept``; an app mirroring the session's
/// undo stacks acts on ``undoEffect``.
public struct CommittedChange: Friendly {
    /// Creates a change description.
    ///
    /// - Parameters:
    ///   - origin: Where the change came from.
    ///   - author: Who made it.
    ///   - applied: The operations applied, with their inverses.
    ///   - invalidation: What the change can have changed.
    ///   - sequence: The session's number for the change.
    ///   - documentRevision: The document's revision after the change.
    ///   - activity: The activity-log events to append.
    ///   - broadcast: The CRDT operations to send to collaborators.
    ///   - isUndoable: Whether the change joined the author's undo history.
    ///   - isDirtying: Whether the change leaves the document differing from its file.
    ///   - kept: Other authors' work an undo left in place.
    ///   - conflicts: What a file merge resolved by keeping the local side.
    ///   - undoEffect: What the change did to the author's undo and redo stacks.
    ///   - rejected: The remote operations refused at the boundary.
    ///   - unrestored: What an undo or redo could not take back and nobody else is to
    ///     credit for.
    public init(
        origin: SessionOrigin.Kind,
        author: Author,
        applied: [AppliedOperation],
        invalidation: ChangeInvalidation,
        sequence: UInt64,
        documentRevision: String,
        activity: [ActivityEvent] = [],
        broadcast: [CRDTOperation] = [],
        isUndoable: Bool,
        isDirtying: Bool,
        kept: [KeptChange] = [],
        conflicts: [MergeConflict] = [],
        undoEffect: UndoEffect = [],
        rejected: [RemoteInputError] = [],
        unrestored: [ChangeKey] = []
    ) {
        self.origin = origin
        self.author = author
        self.applied = applied
        self.invalidation = invalidation
        self.sequence = sequence
        self.documentRevision = documentRevision
        self.activity = activity
        self.broadcast = broadcast
        self.isUndoable = isUndoable
        self.isDirtying = isDirtying
        self.kept = kept
        self.conflicts = conflicts
        self.undoEffect = undoEffect
        self.rejected = rejected
        self.unrestored = unrestored
    }

    /// Where the change came from.
    public var origin: SessionOrigin.Kind

    /// Who made the change: the session's author for a local edit, undo or redo; the
    /// collaborator who sent a remote change; the file's writer for a file merge, or
    /// ``Author/external`` when the log does not say who wrote it.
    public var author: Author

    /// The operations applied, in order, each normalized and with complete, guarded
    /// inverses. Empty for a remote change, which is applied as CRDT operations.
    public var applied: [AppliedOperation]

    /// The nodes and document-level members the change can have changed.
    public var invalidation: ChangeInvalidation

    /// The session's number for this change: one more than the change before it, and
    /// never reused, even after a rollback. A change that applied nothing keeps the
    /// current number rather than taking a new one.
    public var sequence: UInt64

    /// The document's ``EditableDocument/documentRevision`` after the change.
    public var documentRevision: String

    /// The activity-log events to append, one per applied operation. Empty for a
    /// session with no file, and for origins the log does not record as edits.
    public var activity: [ActivityEvent]

    /// The CRDT operations to send to collaborators. Empty outside collaborative mode.
    public var broadcast: [CRDTOperation]

    /// Whether the change joined the author's undo history.
    public var isUndoable: Bool

    /// Whether the change leaves the document differing from its file.
    public var isDirtying: Bool

    /// Other authors' work an undo left in place rather than overwrite.
    public var kept: [KeptChange]

    /// What an undo or a redo could not take back although no other author is to credit
    /// for it, so the app can say so rather than appear to do nothing: the existence of
    /// each node a step needed that is gone, or of each id it would have taken that is in
    /// use — gone through an edit that never joined the undo history, say. Its steps did
    /// not run, and the entry is consumed as for ``kept``. Empty for every other origin.
    public var unrestored: [ChangeKey]

    /// What a file merge could not take from both sides, and resolved — local changes
    /// win a same-key conflict. Empty for every other origin.
    public var conflicts: [MergeConflict]

    /// What the change did to the author's undo and redo stacks — an entry opened or
    /// joined, an entry consumed and its reversal filed, redo cleared — for an app that
    /// mirrors them into its own undo manager. Empty for a change that left both alone.
    public var undoEffect: UndoEffect

    /// The remote operations refused at the boundary, each with why — out-of-range clock
    /// values a buggy or hostile peer sent (``CRDTDocument/validateRemote(_:)``). Nothing
    /// of them was applied. An app reports these and may stop trusting the sender. Empty
    /// for every origin but remote.
    public var rejected: [RemoteInputError]
}
