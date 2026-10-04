//
//  ActivityRecorder.swift
//  Woodcase
//

import Foundation

/// Applies operations to a document *and* records what they did, so an edit cannot be
/// made without being logged.
///
/// A ``PenFileTransaction`` hands one of these to its body alongside the document. Going
/// through ``apply(_:expecting:as:)`` instead of ``EditableDocument/apply(_:expecting:)``
/// is the whole of a caller's obligation to the activity log:
///
/// ```swift
/// try await PenFileTransaction.run(at: url, identity: "ana") { document, recorder in
///     try recorder.apply(.updateCommon(rename))
///     try recorder.apply(.moveNode(reparent))
/// }
/// ```
///
/// Two events, one batch id, each carrying the document's revision *after* its own
/// operation — which is what lets `undo` check one event's revision rather than the
/// whole transaction's.
///
/// ## Through the session
///
/// The recorder is the CLI's door to the library's one edit funnel: it holds a transient
/// ``DocumentSession`` over the transaction's document, under the writer's name, and
/// every operation is a ``SessionOrigin/local(_:)`` submission. The session captures
/// the inverse before it applies, reads each name path from whichever side of the edit
/// still has that node, and keeps the events in its journal, so a run of writes that
/// must be taken back — a batch line that failed part-way — is rolled back with its
/// events in one step. A body that applied operations itself would have to remember all
/// of that; a body that goes through the recorder cannot get it wrong.
///
/// Because it is the session's, an event's inverse is granular and complete: one
/// `setProperties` per property path a whole-struct write changed, one step per
/// override key, and a detach's full restoration. See <doc:WoodcaseActivityLog>.
///
/// ## Every write is recorded, attributed or not
///
/// There is no identity that switches recording off. A transaction opened without a
/// writer's name records its operations under ``ActivityEvent/unattributed`` — the empty
/// name — because an edit that left no trace would fork the history every other reader
/// depends on: `woodcase serve`, `activity --follow`, the viewer's unread marks and
/// `undo` all read the log and nothing else. The one way to edit without a record is to
/// go around the recorder, straight to ``EditableDocument/apply(_:expecting:)``.
///
/// ## Nothing is written here
///
/// The recorder only accumulates. The transaction appends ``events`` to the log after
/// the file is committed, so a body that throws, or one whose edits cancel out, logs
/// nothing.
public final class ActivityRecorder {
    /// Creates a recorder for one transaction.
    ///
    /// - Parameters:
    ///   - document: The document being edited.
    ///   - file: The .pen file the document came from.
    ///   - identity: The writer's `--as` name. `nil` — no `--as` and no
    ///     `$WOODCASE_AS` — is the unattributed writer, recorded as
    ///     ``ActivityEvent/unattributed`` rather than not recorded at all.
    ///   - batch: The id every event of this transaction shares.
    ///   - synced: The document as the file holds it — what the transaction parsed — kept
    ///     as the session's merge base without copying; `nil` when there is none.
    init(document: EditableDocument, file: URL, identity: String?, batch: String, synced: PenDocument? = nil) {
        self.file = file
        self.batch = batch
        session = DocumentSession(
            editing: document,
            author: Author(name: identity ?? ActivityEvent.unattributed, peerID: PeerID.generate()),
            file: file,
            synced: synced,
            activityBatch: batch
        )
        // Starts the journal, which is where the session keeps the events this
        // transaction will append — and what a rolled-back line takes back.
        _ = session.checkpoint()
    }

    /// The session every write goes through: a transient one, over the transaction's
    /// document, under the writer's name, for this transaction alone.
    ///
    /// A caller that must take back a run of writes — ``BatchApplier``'s failed line —
    /// checkpoints and rolls back here, which reverts the document, the ledger and the
    /// recorded events together.
    let session: DocumentSession

    /// The .pen file being edited.
    public let file: URL

    /// The id every event of this transaction shares.
    public let batch: String

    /// The events recorded so far, in the order the operations were applied: any
    /// ``ActivityEvent/Kind/external`` row first, then one per operation the session
    /// has kept.
    public var events: [ActivityEvent] {
        unapplied + session.journaledActivity
    }

    /// Applies an operation through the transaction's ``DocumentSession`` and records
    /// what it did.
    ///
    /// - Parameters:
    ///   - operation: The operation to apply.
    ///   - expecting: Revisions the caller last observed, keyed by node ID, checked
    ///     before anything is applied. A mismatch throws and records nothing.
    ///   - kind: The verb to label the event with, overriding the one derived from the
    ///     operation. `undo` passes ``ActivityEvent/Kind/undo``, `cp` passes
    ///     ``ActivityEvent/Kind/cp``; everything else leaves it `nil`.
    /// - Returns: The event recorded. Every applied operation produces one, whoever
    ///   the writer is. Its inverse is the session's granular one
    ///   (``EditableDocument/granularInverse(of:)``): one step per property path or
    ///   override key, and complete for a detach.
    /// - Throws: ``EditingError/revisionConflict(nodeID:expected:actual:)`` or
    ///   ``EditingError/nodeNotFound(id:)`` from the revision check, and whatever the
    ///   document refuses the operation with. Nothing is recorded when the operation
    ///   does not apply.
    @discardableResult
    public func apply(
        _ operation: EditOperation,
        expecting: [String: String] = [:],
        as kind: ActivityEvent.Kind? = nil
    ) throws -> ActivityEvent {
        try apply([operation], expecting: expecting, as: kind).activity[0]
    }

    /// Applies operations together through the transaction's session: all of them, or —
    /// if one fails — none, with nothing recorded.
    ///
    /// - Parameters:
    ///   - operations: The operations, in order. An empty list applies nothing.
    ///   - expecting: Revisions checked before the first operation is applied.
    ///   - kind: The verb to label every event with, or `nil` to derive each.
    /// - Returns: The committed change, one activity event per operation.
    /// - Throws: Whatever the session refuses the edit with.
    @discardableResult
    func apply(
        _ operations: [EditOperation],
        expecting: [String: String] = [:],
        as kind: ActivityEvent.Kind? = nil
    ) throws -> CommittedChange {
        try session.submit(.local(LocalEdit(operations: operations, expecting: expecting, activityKind: kind)))
    }

    /// Records an event nothing applied.
    ///
    /// There is exactly one: the ``ActivityEvent/Kind/external`` row a
    /// ``PenFileTransaction`` writes when it opens a file the log does not explain. It
    /// is not an operation — nobody applied it through here, and its subject is a change
    /// woodcase did not make — but it belongs in the same append, first, so that the
    /// history reads in order and the invariant the log rests on is restored before the
    /// transaction's own writes land on top of it.
    ///
    /// Internal on purpose: everything else that reaches the log does so by being
    /// applied, which is the whole of the recorder's promise.
    ///
    /// - Parameter event: The event to record.
    func record(_ event: ActivityEvent) {
        unapplied.append(event)
    }

    /// Rows recorded without being applied: the ``ActivityEvent/Kind/external`` row.
    private var unapplied: [ActivityEvent] = []
}
