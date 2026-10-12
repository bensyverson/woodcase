//
//  PenLayoutEdit.swift
//  Woodcase
//

import Foundation

/// One edit a hypothetical layout imagines, by expanded id:
/// ``PenLayoutState/hypothetical(_:)``.
///
/// The edits are the ones a live gesture previews before anything is committed: a row
/// lifted out of a stack, dropped at another index, or resized under the pointer. They
/// change only what layout reads, never the document.
public enum PenLayoutEdit: Friendly {
    /// The node leaves its parent: the gap closes, and a parent that hugs its content
    /// shrinks.
    case remove(String)

    /// The node moves to another index among its parent's children, as
    /// ``EditOperation/MoveNode`` places it: the index is the node's position once it has
    /// been taken out of the list. The parent keeps the same children, so it keeps its
    /// size unless its arrangement depends on their order.
    case move(String, toIndex: Int)

    /// The node takes a fixed size on each axis given; `nil` leaves that axis as it is.
    case size(String, width: Double?, height: Double?)

    /// The node takes a sizing on each axis given; `nil` leaves that axis as it is.
    case sizing(String, width: PenSizing?, height: PenSizing?)

    /// The expanded id of the node the edit acts on.
    public var nodeID: String {
        switch self {
        case let .remove(id), let .move(id, _), let .size(id, _, _), let .sizing(id, _, _): id
        }
    }
}
