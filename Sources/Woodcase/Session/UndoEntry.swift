//
//  UndoEntry.swift
//  Woodcase
//

import Foundation

/// What one press of Undo — or Redo — takes back: the guarded steps of one or more
/// changes by the session's own author.
///
/// An entry is built from the ``AppliedOperation``s of the changes it covers, newest
/// first, so its steps run in the order that takes them back. A coalesced group
/// (``UndoGroup/coalesce(_:)``) adds each later change's steps in front of the ones
/// already there.
struct UndoEntry: Friendly {
    /// The steps that take back one applied operation.
    ///
    /// A reversal that adds, removes, moves or rebuilds nodes stands or falls as a
    /// whole: undoing a detach is "remove the expansion" *and* "put the instance back",
    /// and doing one without the other would duplicate or lose the content. A reversal
    /// that only writes properties, overrides or document members is weighed step by
    /// step, so one contested key does not hold back its neighbors.
    struct Reversal: Friendly {
        /// The steps, in the order they apply.
        var steps: [GuardedInverse]
    }

    /// The sequence of the earliest change the entry covers. Another author's write to
    /// one of its keys with a later sequence is theirs to keep.
    var sequence: UInt64

    /// The reversals, in the order they apply: the newest operation's first.
    var reversals: [Reversal]

    /// Creates an entry from reversals already in apply order.
    ///
    /// - Parameters:
    ///   - sequence: The sequence of the earliest change the entry covers.
    ///   - reversals: The reversals, the newest operation's first.
    init(sequence: UInt64, reversals: [Reversal]) {
        self.sequence = sequence
        self.reversals = reversals
    }

    /// An entry that takes back a run of applied operations.
    ///
    /// - Parameters:
    ///   - applied: The operations, in the order they were applied.
    ///   - sequence: The sequence of the change that applied them.
    init(undoing applied: [AppliedOperation], at sequence: UInt64) {
        self.sequence = sequence
        reversals = applied.reversed().map { Reversal(steps: $0.inverse) }
    }

    /// Folds a later change into this entry, so one undo takes back both.
    ///
    /// - Parameter later: The entry for the later change.
    mutating func absorb(_ later: UndoEntry) {
        reversals = later.reversals + reversals
    }
}
