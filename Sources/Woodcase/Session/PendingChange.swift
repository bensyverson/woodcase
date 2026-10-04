//
//  PendingChange.swift
//  Woodcase
//

import Foundation

/// A change a session is part-way through applying: what has landed so far, before it
/// is numbered, stamped and described.
///
/// A local edit and an undo or redo build one the same way, an operation at a time, so
/// both reach the document, the CRDT and the activity log by the same path.
struct PendingChange: Friendly {
    /// Creates an empty change.
    ///
    /// - Parameters:
    ///   - batch: The batch id every activity event of the change shares.
    ///   - activityKind: The verb every activity event is labeled with, or `nil` to
    ///     label each by its operation.
    init(batch: String = UUID().uuidString, activityKind: ActivityEvent.Kind? = nil) {
        self.batch = batch
        self.activityKind = activityKind
    }

    /// The batch id every activity event of the change shares.
    let batch: String

    /// The verb every activity event is labeled with, or `nil` to label each by its
    /// operation.
    let activityKind: ActivityEvent.Kind?

    /// The operations applied so far, with their inverses.
    var applied: [AppliedOperation] = []

    /// The CRDT operations to broadcast.
    var broadcast: [CRDTOperation] = []

    /// The keys written, to stamp once the change commits.
    var keys: [ChangeKey] = []

    /// What the change can have changed.
    var invalidation = ChangeInvalidation()

    /// The activity events to append.
    var activity: [ActivityEvent] = []
}
