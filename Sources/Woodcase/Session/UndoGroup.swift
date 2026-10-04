//
//  UndoGroup.swift
//  Woodcase
//

import Foundation

/// How a local edit joins the author's undo history.
///
/// A session owns its author's undo stack, so it decides what one press of Undo
/// takes back. A drag that submits a hundred moves wants one entry, not a hundred;
/// an edit that only tidies up after another wants none at all.
public enum UndoGroup: Friendly {
    /// The edit is a new undo entry of its own.
    case new

    /// The edit joins the most recent entry when that entry was opened with the same
    /// key, and starts a new entry with that key otherwise.
    case coalesce(String)

    /// The edit is applied but cannot be undone on its own.
    case none
}
