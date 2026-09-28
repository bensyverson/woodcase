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
/// ## Order matters, and the recorder gets it right
///
/// The inverse of an operation can only be captured *before* it is applied, and a name
/// path is only meaningful in the state where the node exists. The recorder takes the
/// inverse first, applies, then reads each name path from whichever side of the edit
/// still has that node: after it for a node that survived, before it for one the
/// operation removed. A body that applied operations itself would have to remember all
/// of that; a body that goes through the recorder cannot get it wrong.
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
    init(document: EditableDocument, file: URL, identity: String?, batch: String) {
        self.document = document
        self.file = file
        self.identity = identity ?? ActivityEvent.unattributed
        self.batch = batch
    }

    /// The .pen file being edited.
    public let file: URL

    /// The id every event of this transaction shares.
    public let batch: String

    /// The events recorded so far, in the order the operations were applied.
    public private(set) var events: [ActivityEvent] = []

    /// Applies an operation and records what it did.
    ///
    /// - Parameters:
    ///   - operation: The operation to apply.
    ///   - expecting: Revisions the caller last observed, keyed by node ID, checked
    ///     before anything is applied. A mismatch throws and records nothing.
    ///   - kind: The verb to label the event with, overriding the one derived from the
    ///     operation. `undo` passes ``ActivityEvent/Kind/undo``, `cp` passes
    ///     ``ActivityEvent/Kind/cp``; everything else leaves it `nil`.
    /// - Returns: The event recorded. Every applied operation produces one, whoever
    ///   the writer is.
    /// - Throws: ``EditingError/revisionConflict(nodeID:expected:actual:)`` or
    ///   ``EditingError/nodeNotFound(id:)`` from the revision check, and anything
    ///   ``EditableDocument/prepareInverse(of:)`` or ``EditableDocument/apply(_:)``
    ///   throws. Nothing is recorded when the operation does not apply.
    @discardableResult
    public func apply(
        _ operation: EditOperation,
        expecting: [String: String] = [:],
        as kind: ActivityEvent.Kind? = nil
    ) throws -> ActivityEvent {
        let inverse = try document.prepareInverse(of: operation)
        let nodes = ActivityEvent.nodeIDs(touchedBy: operation)
        let pathsBefore = nodes.map(document.namePath(of:))

        try document.apply(operation, expecting: expecting)

        let paths = zip(nodes, pathsBefore).map { nodeID, before in
            document.nodes[nodeID] == nil ? before : document.namePath(of: nodeID)
        }
        let event = ActivityEvent(
            time: Date(),
            identity: identity,
            file: file,
            op: kind ?? ActivityEvent.Kind(operation),
            nodes: nodes,
            paths: paths,
            inverse: inverse,
            revision: document.documentRevision,
            batch: batch
        )
        events.append(event)
        return event
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
        events.append(event)
    }

    /// Drops every event recorded after a checkpoint.
    ///
    /// The checkpoint is `events.count` taken before the run of operations in
    /// question. This exists for one caller: ``BatchApplier``, whose unit of work is a
    /// *line*, not an operation. A line that fails half way through is unwound with
    /// the inverses of the operations it already applied, and the events those
    /// operations recorded describe edits the document no longer has — so the line
    /// leaves no trace at all, exactly as a line that failed on its first operation
    /// would. The unwind itself goes straight to the document and records nothing.
    ///
    /// It is deliberately not public: dropping events is the one thing a recorder
    /// exists to prevent, and rolling a line back is the only honest reason to do it.
    ///
    /// - Parameter count: The number of events to keep. A `count` at or past
    ///   ``events``'s length keeps everything.
    func discardEvents(after count: Int) {
        guard count < events.count else { return }
        events.removeSubrange(max(0, count)...)
    }

    /// The document being edited.
    private let document: EditableDocument

    /// The writer's `--as` name, or ``ActivityEvent/unattributed`` when nobody claimed
    /// the write.
    private let identity: String
}
