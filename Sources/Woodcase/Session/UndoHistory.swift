//
//  UndoHistory.swift
//  Woodcase
//

import Foundation

/// A session author's undo and redo stacks, and the coalescing group still open.
///
/// A value, so a checkpoint keeps a copy and a rollback puts it back with the
/// document and the ledger.
struct UndoHistory: Friendly {
    /// Entries Undo takes back, the most recent last.
    var undo: [UndoEntry] = []

    /// Entries Redo puts back, the most recently undone last.
    var redo: [UndoEntry] = []

    /// The ``UndoGroup/coalesce(_:)`` key of the most recent undo entry, while a
    /// change with the same key may still join it; `nil` once anything else is pushed,
    /// or after an undo or redo.
    var openGroup: String?

    /// Records a local change: joins its group, clears redo.
    ///
    /// A change that joins no group (``UndoGroup/none``) still clears redo, since what
    /// redo would put back was taken from a document that has since moved on; it
    /// leaves an open group open, so a tidy-up mid-drag does not split the drag.
    ///
    /// - Parameters:
    ///   - entry: The change's entry.
    ///   - group: How the change joins the history.
    mutating func record(_ entry: UndoEntry, group: UndoGroup) {
        redo.removeAll()
        switch group {
        case .none:
            return
        case .new:
            undo.append(entry)
            openGroup = nil
        case let .coalesce(key):
            if openGroup == key, let last = undo.indices.last {
                undo[last].absorb(entry)
            } else {
                undo.append(entry)
                openGroup = key
            }
        }
    }
}
