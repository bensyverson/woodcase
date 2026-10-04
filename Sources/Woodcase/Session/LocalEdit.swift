//
//  LocalEdit.swift
//  Woodcase
//

import Foundation

/// An edit by a session's own author: operations applied together, or not at all.
///
/// ```swift
/// let edit = LocalEdit(
///     operations: [.moveNode(EditOperation.MoveNode(nodeID: "c2", newParentID: "f2"))],
///     expecting: ["c2": revision]
/// )
/// let change = try session.submit(.local(edit))
/// ```
public struct LocalEdit: Friendly {
    /// Creates an edit.
    ///
    /// - Parameters:
    ///   - operations: The operations, applied in order.
    ///   - expecting: Revisions the author last observed, keyed by node id. Every entry
    ///     is checked before anything is applied.
    ///   - activityKind: The verb every activity event of this edit is labeled with, or
    ///     `nil` to label each by its operation.
    ///   - undoGroup: How the edit joins the author's undo history.
    public init(
        operations: [EditOperation],
        expecting: [String: String] = [:],
        activityKind: ActivityEvent.Kind? = nil,
        undoGroup: UndoGroup = .new
    ) {
        self.operations = operations
        self.expecting = expecting
        self.activityKind = activityKind
        self.undoGroup = undoGroup
    }

    /// The operations, applied in order. If one fails, the ones before it are undone.
    public var operations: [EditOperation]

    /// Revisions the author last observed, keyed by node id, checked before anything is
    /// applied. A mismatch refuses the whole edit with
    /// ``EditingError/revisionConflict(nodeID:expected:actual:)``.
    public var expecting: [String: String]

    /// The verb every activity event of this edit is labeled with, such as
    /// ``ActivityEvent/Kind/cp`` for an insert that is a copy; `nil` labels each event
    /// by its operation.
    public var activityKind: ActivityEvent.Kind?

    /// How the edit joins the author's undo history.
    public var undoGroup: UndoGroup
}
