//
//  DocumentSession+Checkpoint.swift
//  Woodcase
//

import Foundation

extension DocumentSession {
    /// Marks a point to roll back to if a run of submissions fails.
    ///
    /// The first checkpoint starts the session's journal, which keeps every change
    /// committed from then on so ``rollback(to:)`` can take them back. A long-lived
    /// session that never checkpoints keeps no journal.
    ///
    /// - Returns: The checkpoint.
    func checkpoint() -> SessionCheckpoint {
        let journal = journal ?? []
        self.journal = journal
        return SessionCheckpoint(
            sequence: sequence,
            journalCount: journal.count,
            ledger: ledger,
            lastDirtyingSequence: lastDirtyingSequence
        )
    }

    /// Takes back every change committed since a checkpoint.
    ///
    /// The document, the ledger, the journaled activity and the unsynced state return
    /// to the checkpoint together. The sequence does not: numbers already handed out
    /// are never reused, so a snapshot taken in between cannot be confused with a later
    /// change. If the file was synced past the checkpoint, it now holds work the
    /// document no longer has, so the session counts as unsynced.
    ///
    /// - Parameter checkpoint: A checkpoint this session took.
    /// - Returns: The CRDT operations that take the changes back, for collaborators
    ///   who already received them; empty outside collaborative mode.
    @discardableResult
    func rollback(to checkpoint: SessionCheckpoint) -> [CRDTOperation] {
        guard let journal, checkpoint.journalCount <= journal.count else { return [] }
        let undone = journal[checkpoint.journalCount...]
        let broadcast = unwind(undone.flatMap(\.applied))
        self.journal = Array(journal[..<checkpoint.journalCount])
        ledger = checkpoint.ledger
        lastDirtyingSequence = checkpoint.lastDirtyingSequence
        if syncedSequence > checkpoint.sequence {
            fileHoldsRolledBackWork = true
        }
        return broadcast
    }

    /// The activity events of every change in the journal, in order: what a run of
    /// submissions has to append to the log once it succeeds.
    var journaledActivity: [ActivityEvent] {
        journal?.flatMap(\.activity) ?? []
    }
}
