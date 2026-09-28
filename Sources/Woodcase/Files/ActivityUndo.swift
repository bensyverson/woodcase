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
                afterUndo: afterUndo
            )
            switch decision {
            case .undo:
                for operation in event.inverse {
                    try recorder.apply(operation, as: .undo)
                }
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
            case .reachedCreation:
                break walk
            case .blockedByOther, .blockedByStale, .blockedByExternal:
                stopped = decision
                break walk
            }
        }
        return Result(undone: undone, stopped: stopped, recorded: recorded.count)
    }
}
