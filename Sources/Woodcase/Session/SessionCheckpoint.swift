//
//  SessionCheckpoint.swift
//  Woodcase
//

import Foundation

/// A point a ``DocumentSession`` can be rolled back to.
///
/// Taken by ``DocumentSession/checkpoint()`` before a run of submissions that must land
/// together or not at all — a batch line, a CLI verb — and handed to
/// ``DocumentSession/rollback(to:)`` if the run fails. The document, the ledger, the
/// journaled activity and the unsynced state all return to this point together.
struct SessionCheckpoint: Friendly {
    /// The session's sequence when the checkpoint was taken.
    var sequence: UInt64

    /// How many changes the session's journal held.
    var journalCount: Int

    /// The ledger as it stood.
    var ledger: ChangeLedger

    /// The sequence of the last dirtying change.
    var lastDirtyingSequence: UInt64
}
