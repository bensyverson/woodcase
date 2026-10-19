//
//  ActivityChangeSummary.swift
//  Woodcase
//

import Foundation

/// One activity row read as what changed: each property, node, variable or import it
/// touched, with the value before and the value after.
///
/// An ``ActivityEvent`` records the operations a writer applied (``ActivityEvent/forward``)
/// and the operations that undo them (``ActivityEvent/inverse``). Neither answers "what
/// did Ben change?" on its own: a whole-struct `updateCommon` carries every common
/// property whether or not it moved, and an inverse holds only the values *before*. The
/// summary pairs the two — new values from the forward side, old values from the
/// inverse — and keeps only what actually differs:
///
/// ```swift
/// let summary = ActivityChangeSummary(event)
/// summary.changes.map(\.line)
/// // ["Home/Hero/Title  kind.content: \"Welcome\" → \"Welcome back\""]
/// ```
///
/// It reads the event alone, never the document: the log is the record, and a value
/// reconstructed from a later state of the file could be wrong. `woodcase changes`
/// prints these; Penumbra or any other reader can build its own feed on them.
///
/// ## Pairing
///
/// - A property is keyed by node and path — the `common.name` / `kind.width`
///   vocabulary `woodcase set` takes — so a change can be repeated or answered with one
///   `set`. Its old value is the last write the inverse makes to that key (the inverse
///   runs in order, so the last write is the state before the row); its new value is the
///   last write the forward side makes. A whole-struct update reads its changed keys
///   from a granular inverse, or diffs a whole-struct inverse with ``PropertyDiff``.
/// - A write that leaves a key as it was is no change and is left out.
/// - Inserts, deletes, moves, replaces and detaches are one change each.
/// - Overrides are keyed by instance, descendant and override key; variables, imports
///   and theme axes by name; document properties by key.
/// - A row with nothing to pair — an outside write, a migration, a row logged before
///   `forward` existed — still yields one change, so every row has a line.
public struct ActivityChangeSummary: Friendly {
    /// Reads an event as its changes.
    ///
    /// - Parameter event: The activity row to summarize.
    public init(_ event: ActivityEvent) {
        time = event.time
        identity = event.identity
        file = event.file
        op = event.op
        revision = event.revision
        batch = event.batch
        var pairing = Pairing(event)
        changes = pairing.changes()
    }

    /// When the row was written.
    public var time: Date

    /// Who wrote it — the `--as` name, or ``ActivityEvent/unattributed``.
    public var identity: String

    /// The canonical path of the .pen file it edited.
    public var file: String

    /// The row's own verb, as the log recorded it — `undo` and `merge` included.
    public var op: ActivityEvent.Kind

    /// The document's revision after the row.
    public var revision: String

    /// The transaction the row belongs to, shared by every row one command wrote.
    public var batch: String?

    /// What changed, one entry per property, node or named thing, in the order the
    /// writer touched them.
    public var changes: [Change]
}
