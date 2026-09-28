//
//  UndoUnit.swift
//  Woodcase
//

import Foundation

/// What one step of an undo reverses.
///
/// A person who ran one command expects one undo to take it back, and a command is a
/// ``PenFileTransaction`` however many operations it applied: `cp --times 3` is six
/// events, a batch is as many as it has lines, and a script run can be forty. Counting
/// those one at a time made "undo what I just did" a chore whose length the reader had
/// to look up in the log first.
///
/// So ``transaction`` is the default and the unit `-n` counts. ``event`` is the older,
/// finer form, kept because the log's row is a real thing to point at and a reader who
/// wants exactly one row back should be able to say so.
public enum UndoUnit: String, Friendly, CaseIterable {
    /// One whole transaction: every event sharing the newest batch id, reversed in the
    /// opposite order to the one it was applied in.
    case transaction

    /// One logged event.
    case event
}
