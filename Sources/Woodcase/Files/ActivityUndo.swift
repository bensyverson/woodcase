//
//  ActivityUndo.swift
//  Woodcase
//

import Foundation

/// Reverses the tail of the activity log against the document it describes.
///
/// This is `woodcase undo`, minus the argv and the sentences: the walk back through the
/// log, the revision checks that make each inverse exact, and the replay through an
/// ``ActivityRecorder`` so the reversal is itself recorded. A library caller with a log
/// and a transaction can undo an edit without going through the CLI:
///
/// ```swift
/// try await PenFileTransaction.run(at: url, identity: "ana") { document, recorder in
///     try ActivityUndo.reverse(in: document, through: recorder, editing: url, identity: "ana")
/// }
/// ```
///
/// ## Read under the lock
///
/// The log is read *inside* the transaction's body, so it is read under the same lock
/// that guards the .pen file: no other writer can commit an edit between the read and
/// the revision check.
///
/// ## What a step is
///
/// By default a step is one whole transaction — every event sharing one batch id,
/// reversed in the opposite order to the one it was applied in — because that is what
/// the reader ran. ``UndoUnit/event`` reverses one row of the log instead. See
/// ``UndoUnit``.
///
/// The walk is one event at a time either way; what a transaction changes is only
/// whether the next event *counts* against `limit`. That is what makes the two units
/// compose: after an ``UndoUnit/event`` undo has taken the last row of a command, a
/// plain undo finishes the rest of that command as one step, because each remaining row
/// is judged on its own revision and they share a batch id. Grouping the rows up front
/// instead would have judged the command by a row that was already reversed, and
/// answered "nothing to undo" to a reader who could see five rows left.
///
/// ## Where it stops
///
/// The walk stops at the first step it cannot reverse and says which one, rather than
/// throwing: a run that reversed two steps and then met somebody else's edit keeps the
/// two — discarding good work to report a refusal helps nobody — and the caller decides
/// how loudly to say why. A run that reversed *nothing* returns an empty ``Result``
/// with the same ``Result/stopped`` step, and the caller's transaction, having changed
/// nothing, writes nothing.
public enum ActivityUndo {
    /// What one reversal produced.
    public struct Result: Friendly {
        /// Describes a finished reversal.
        ///
        /// - Parameters:
        ///   - undone: The events reversed, newest first.
        ///   - stopped: The step that ended the walk early, or `nil` if none did.
        ///   - recorded: How many events the log holds for this file.
        public init(undone: [ActivityEvent], stopped: UndoStep?, recorded: Int) {
            self.undone = undone
            self.stopped = stopped
            self.recorded = recorded
        }

        /// The events whose inverses were replayed, in the order they were reversed —
        /// newest first, so the list reads as the history running backwards.
        public var undone: [ActivityEvent]

        /// The step the walk refused to go past, or `nil` when it stopped because it
        /// had reversed everything it was asked for, or run out of log.
        ///
        /// Always one of ``UndoStep/blockedByOther(_:)``, ``UndoStep/blockedByStale(_:)``
        /// or ``UndoStep/blockedByExternal(_:)``.
        public var stopped: UndoStep?

        /// How many events the log holds for this file, so a caller reporting "nothing
        /// to undo" can tell an unlogged file from one whose history is all undone.
        public var recorded: Int
    }

    /// Walks the log's tail for one file, newest-first, replaying inverses.
    ///
    /// - Parameters:
    ///   - document: The document the transaction opened.
    ///   - recorder: The recorder every inverse is applied through, so each one is
    ///     logged as an ``ActivityEvent/Kind/undo`` event. Events it has *already*
    ///     recorded — the ``ActivityEvent/Kind/external`` row a transaction records when
    ///     it finds the file changed behind the log's back — count as the newest part of
    ///     the tail, which is what makes an undo refuse to step past an outside edit it
    ///     is the first to notice.
    ///   - url: The .pen file being undone.
    ///   - log: The log to read. `nil` resolves the file's own through
    ///     ``ActivityLogLocation``, which is what every verb wants.
    ///   - identity: The name running the undo. Its own events are the candidates.
    ///   - allIdentities: Whether every identity's events are candidates.
    ///   - limit: How many steps to reverse at most.
    ///   - unit: What one step is. See ``UndoUnit``.
    /// - Returns: What was reversed, and what stopped the walk.
    /// - Throws: ``PenFileError`` if the log cannot be read, and anything
    ///   ``ActivityRecorder/apply(_:expecting:as:)`` throws while replaying an inverse.
    @discardableResult
    public static func reverse(
        in document: EditableDocument,
        through recorder: ActivityRecorder,
        editing url: URL,
        log: ActivityLog? = nil,
        identity: String,
        allIdentities: Bool = false,
        limit: Int = 1,
        unit: UndoUnit = .transaction
    ) throws -> Result {
        let recorded = try ActivityReader(log: log ?? ActivityLogLocation.log(for: url))
            .read(file: url).events
        let events = recorded + recorder.events

        var undone: [ActivityEvent] = []
        var stopped: UndoStep?
        var steps = 0
        var afterUndo = false
        // The batch id of the event just reversed, or nil when the last thing the walk
        // did was anything else. An event carrying the same id belongs to the same
        // command and rides along inside the step already counted.
        var continuing: String?
        var index = events.count - 1
        // Past a merge row: the document without the work it folded in, and the nodes
        // that work touched. See ``unfold(_:from:)``.
        var unfolding: Unfolding?

        walk: while index >= 0 {
            let event = events[index]
            let continues = unit == .transaction && continuing != nil && event.batch == continuing
            guard continues || steps < limit else { break }
            index -= 1
            let decision = UndoStep.decide(
                event,
                currentRevision: document.documentRevision,
                identity: identity,
                allIdentities: allIdentities,
                afterUndo: afterUndo,
                unfolded: unfolding.map { UndoStep.Unfolded(
                    revision: $0.document.documentRevision,
                    touchesFoldedWork: $0.touches(event, in: document)
                ) }
            )
            switch decision {
            case .undo:
                // One local edit per event, labeled undo: the event's inverse lands
                // whole or not at all, through the same session as any other write.
                try recorder.apply(event.inverse, as: .undo)
                unfolding?.replay(event.inverse)
                undone.append(event)
                if !continues { steps += 1 }
                // An external row is nobody's command, so nothing rides along with it.
                continuing = event.op == .external ? nil : event.batch
            case .stepOverUndo:
                afterUndo = true
                continuing = nil
            case .stepOverUndone:
                continuing = nil
            case .stepOverRewrite:
                // Does not end a command's run of events either: a migrate is between
                // two commands, never inside one, so the batch id decides as before.
                break
            case .stepOverMerge:
                // Not a command either: the batch id decides as before.
                unfolding = Self.unfold(event, from: unfolding?.document ?? document)
                    .map { $0.adding(unfolding?.folded ?? []) }
            case .reachedCreation:
                break walk
            case .blockedByOther, .blockedByStale, .blockedByExternal:
                stopped = decision
                break walk
            }
        }
        return Result(undone: undone, stopped: stopped, recorded: recorded.count)
    }

    /// The document as it would be without a merge row's folded-in work, so the rows
    /// below it can still be judged exactly.
    ///
    /// A ``ActivityEvent/Kind/merge`` row's inverse takes the folded-in work back out of
    /// the state the row recorded. When the document — or the unfolded document of a
    /// merge row above — is in that state, replaying the inverse on a copy gives the
    /// state the session's own rows were written against, and their revisions chain
    /// again. Otherwise — a row with no inverse (the work came from a collaborator), or a
    /// state something has moved on from — there is nothing exact to judge by, and the
    /// rows below are judged against the document as usual.
    ///
    /// - Parameters:
    ///   - row: The merge row.
    ///   - document: The document, or the unfolded document of a merge row above.
    /// - Returns: The unfolded document and the nodes the folded-in work touched, or
    ///   `nil` when it cannot be built exactly.
    private static func unfold(_ row: ActivityEvent, from document: EditableDocument) -> Unfolding? {
        guard !row.inverse.isEmpty, LogLineage.explains(row, at: document.documentRevision) else { return nil }
        let unfolded = EditableDocument(from: document.materialize())
        do {
            for operation in row.inverse {
                try unfolded.apply(operation)
            }
        } catch {
            return nil
        }
        return Unfolding(document: unfolded, folded: Set(row.nodes))
    }

    /// The walk's view past one or more merge rows.
    ///
    /// Not `Friendly`: it holds an ``EditableDocument``, a reference type that is
    /// neither `Codable` nor `Sendable`, and it never leaves the walk.
    private struct Unfolding {
        /// The document without the folded-in work.
        let document: EditableDocument

        /// Every node the folded-in work touched.
        let folded: Set<String>

        /// The same view, also counting the nodes of merge rows above it.
        func adding(_ nodes: Set<String>) -> Unfolding {
            Unfolding(document: document, folded: folded.union(nodes))
        }

        /// Replays an undone row's inverse on the unfolded document too, so the next
        /// row down is judged against the state before it.
        func replay(_ inverse: [EditOperation]) {
            for operation in inverse {
                try? document.apply(operation)
            }
        }

        /// Whether undoing an event would reach folded-in work: its subject is a node
        /// the work touched, or holds one in the document.
        func touches(_ event: ActivityEvent, in document: EditableDocument) -> Bool {
            guard let subject = event.nodes.first else { return false }
            return folded.contains { node in
                node == subject || document.ancestors(of: node).contains(subject)
            }
        }
    }
}
