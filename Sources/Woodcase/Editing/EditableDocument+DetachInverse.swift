//
//  EditableDocument+DetachInverse.swift
//  Woodcase
//

import Foundation

/// The inverse of a detach, complete before the detach runs.
///
/// A detach's ids are derived from the document (``detachPlans(for:)``), so the
/// expanded root it will insert is named before anything is written, and the inverse
/// — remove that subtree, put the ref back where it was — is whole from the start.
/// That is what lets ``ActivityRecorder``, `BatchApplier`'s rollback and any other
/// caller of ``prepareInverse(of:)`` undo a detach with no completion step.
extension EditableDocument {
    /// Inverse of detachRef: remove the expansion the detach will insert, then restore
    /// the ref — its whole subtree, at its index.
    ///
    /// - Parameter op: The detach about to be applied.
    /// - Returns: `[deleteNode(expanded root), insertNode(ref)]`.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` or ``EditingError/notARefNode(id:)``.
    func prepareInverseDetachRef(_ op: EditOperation.DetachRef) throws -> [EditOperation] {
        guard let plan = try detachPlans(for: [op.refNodeID]).first else {
            throw EditingError.notARefNode(id: op.refNodeID)
        }
        return try detachInverse(of: plan)
    }

    /// The two steps that undo one planned detach.
    ///
    /// - Parameter plan: The detach, from ``detachPlans(for:)``.
    /// - Returns: `[deleteNode(expanded root), insertNode(ref)]`.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if the ref is gone.
    func detachInverse(of plan: PlannedDetach) throws -> [EditOperation] {
        try [
            .deleteNode(EditOperation.DeleteNode(nodeID: plan.subtree.id)),
            .insertNode(EditOperation.InsertNode(
                node: materializeSubtree(rootID: plan.refID),
                parentID: plan.parentID,
                index: plan.index
            )),
        ]
    }
}

public extension EditableDocument {
    /// Returns a detach's inverse unchanged.
    ///
    /// ``prepareInverse(of:)`` used to return only the re-insert for a detach, because
    /// the expanded ids were drawn at random and unknown until the detach ran; this
    /// prepended the delete. The ids are now derived, so the prepared inverse is
    /// already complete and there is nothing left to add.
    ///
    /// - Parameters:
    ///   - expandedRootID: The root node ID from the detach result. Ignored.
    ///   - partialInverse: The inverse from ``prepareInverse(of:)``.
    /// - Returns: `partialInverse`, as given.
    @available(*, deprecated, message: "prepareInverse(of:) is complete for a detach; use its result directly")
    func completeDetachInverse(
        expandedRootID _: String,
        partialInverse: [EditOperation]
    ) -> [EditOperation] {
        partialInverse
    }

    /// Returns a detaching delete's inverse unchanged.
    ///
    /// The counterpart of ``completeDetachInverse(expandedRootID:partialInverse:)`` for
    /// a delete that detaches the instances it would strand: ``prepareInverse(of:)``
    /// already names the expanded roots those detaches will produce.
    ///
    /// - Parameters:
    ///   - detached: The results from ``deleteNode(_:)``. Ignored.
    ///   - partialInverse: The inverse from ``prepareInverse(of:)``.
    /// - Returns: `partialInverse`, as given.
    @available(*, deprecated, message: "prepareInverse(of:) is complete for a detaching delete; use its result directly")
    func completeDetachingDeleteInverse(
        detached _: [DetachResult],
        partialInverse: [EditOperation]
    ) -> [EditOperation] {
        partialInverse
    }
}
