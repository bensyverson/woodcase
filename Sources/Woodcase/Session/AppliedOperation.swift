//
//  AppliedOperation.swift
//  Woodcase
//

import Foundation

/// One operation a session applied, with the steps that undo it.
public struct AppliedOperation: Friendly {
    /// Creates an applied operation.
    ///
    /// - Parameters:
    ///   - forward: The operation as applied, normalized.
    ///   - inverse: The steps that undo it, in the order they apply.
    public init(forward: EditOperation, inverse: [GuardedInverse]) {
        self.forward = forward
        self.inverse = inverse
    }

    /// The operation as applied, in the per-path vocabulary of
    /// ``EditOperation/normalized(in:)``: a whole-struct `updateCommon` arrives here as
    /// the `setProperties` of the paths it changed.
    public var forward: EditOperation

    /// The steps that undo ``forward``, captured before it applied and complete —
    /// a detach's include re-inserting the instance — each guarded by the keys it
    /// restores (``EditableDocument/granularInverse(of:)``).
    public var inverse: [GuardedInverse]
}
