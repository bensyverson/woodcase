//
//  CommittedChange+Folding.swift
//  Woodcase
//

import Foundation

public extension CommittedChange {
    /// One change standing for a run of changes — consecutive changes of one origin by
    /// one author, oldest first — for an app to save in their place, so the run reaches
    /// the activity log as one row per kind of edit rather than one per change.
    ///
    /// An editor that commits every keystroke (so its own view is always the document)
    /// folds a typing step's changes before the save that sends them to agents:
    /// ```swift
    /// if let step = CommittedChange.folding(Array(unsaved[stepStart...])) {
    ///     unsaved.replaceSubrange(stepStart..., with: [step])
    /// }
    /// ```
    ///
    /// - ``activity`` is ``ActivityEvent/folding(_:)`` of every change's rows — a typed
    ///   word on one text is one row whose inverse restores the text before the step and
    ///   whose forward writes it after — all under the first row's batch id, so
    ///   `woodcase undo` takes the run back as one step;
    /// - ``sequence`` and ``documentRevision`` are the last change's, so
    ///   ``PenFileTransaction/save(_:changes:to:log:timeout:)`` includes the folded change
    ///   exactly when it would have included the last of the run, and its last row
    ///   explains the saved revision;
    /// - ``applied``, ``broadcast``, ``kept``, ``unrestored`` and ``conflicts`` are every change's, in
    ///   order; ``invalidation`` and ``undoEffect`` their union; it is undoable or
    ///   dirtying when any of them is.
    ///
    /// Folding changes nothing in the session: its undo history, ledger and synced
    /// revision stand as the changes left them, so the session's undo and redo work as
    /// before.
    ///
    /// - Parameter changes: The run, oldest first.
    /// - Returns: The folded change, or `nil` when `changes` is empty or mixes origins or
    ///   authors.
    static func folding(_ changes: [CommittedChange]) -> CommittedChange? {
        guard let first = changes.first, let last = changes.last,
              changes.allSatisfy({ $0.origin == first.origin && $0.author == first.author })
        else { return nil }
        var activity = ActivityEvent.folding(changes.flatMap(\.activity))
        let batch = activity.first?.batch
        for index in activity.indices {
            activity[index].batch = batch
        }
        return CommittedChange(
            origin: first.origin,
            author: first.author,
            applied: changes.flatMap(\.applied),
            invalidation: changes.reduce(into: ChangeInvalidation()) { $0.formUnion($1.invalidation) },
            sequence: last.sequence,
            documentRevision: last.documentRevision,
            activity: activity,
            broadcast: changes.flatMap(\.broadcast),
            isUndoable: changes.contains(where: \.isUndoable),
            isDirtying: changes.contains(where: \.isDirtying),
            kept: changes.flatMap(\.kept),
            conflicts: changes.flatMap(\.conflicts),
            undoEffect: changes.reduce(into: UndoEffect()) { $0.formUnion($1.undoEffect) },
            unrestored: changes.flatMap(\.unrestored)
        )
    }
}
