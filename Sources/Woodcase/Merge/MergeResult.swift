//
//  MergeResult.swift
//  Woodcase
//

import Foundation

/// What a three-way merge produced: the operations that fold the external side into
/// the local document, and what it could not take from both.
public struct MergeResult: Friendly {
    /// The operations that turn the local document into the merged one, to apply in
    /// order. Indices are absolute and valid in sequence: each operation assumes every
    /// one before it has been applied.
    public var operations: [EditOperation]

    /// Everything the merge resolved by keeping one side, in a stable order.
    public var conflicts: [MergeConflict]

    /// Whether the merged document still differs from the external one — local work
    /// survived the merge, so a session that adopted the file stays dirty.
    public var keepsLocalChanges: Bool

    /// Creates a merge result.
    ///
    /// - Parameters:
    ///   - operations: The operations to apply to the local document, in order.
    ///   - conflicts: What the merge resolved by keeping one side.
    ///   - keepsLocalChanges: Whether the merged document differs from the external one.
    public init(operations: [EditOperation] = [], conflicts: [MergeConflict] = [], keepsLocalChanges: Bool = false) {
        self.operations = operations
        self.conflicts = conflicts
        self.keepsLocalChanges = keepsLocalChanges
    }
}
