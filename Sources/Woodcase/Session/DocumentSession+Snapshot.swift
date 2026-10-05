//
//  DocumentSession+Snapshot.swift
//  Woodcase
//

import Foundation

public extension DocumentSession {
    /// The document as it stands, as a value for background work.
    ///
    /// The session itself cannot leave its owner's isolation domain; the snapshot can.
    /// Save it, render it or export it from any task, then report a save back with
    /// ``noteSynced(_:)``.
    ///
    /// ```swift
    /// let snapshot = session.snapshot()
    /// if try await PenFileTransaction.save(snapshot, changes: unsaved, to: url).isSynced {
    ///     session.noteSynced(snapshot)
    /// }
    /// ```
    ///
    /// - Returns: The materialized document with its sequence, its revision and the
    ///   revision of what the file holds.
    func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            document: document.materialize(),
            sequence: sequence,
            documentRevision: document.documentRevision,
            syncedRevision: syncedRevision,
            author: author
        )
    }
}
