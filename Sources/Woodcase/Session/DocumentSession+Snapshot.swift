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
    /// ``noteSynced(_:through:)``.
    ///
    /// ```swift
    /// let snapshot = session.snapshot()
    /// try await Task.detached { try writer.write(snapshot.document, to: url) }.value
    /// session.noteSynced(snapshot.document, through: snapshot.sequence)
    /// ```
    ///
    /// - Returns: The materialized document with its sequence and revision.
    func snapshot() -> DocumentSnapshot {
        DocumentSnapshot(
            document: document.materialize(),
            sequence: sequence,
            documentRevision: document.documentRevision
        )
    }
}
