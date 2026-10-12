//
//  GuardedInverse.swift
//  Woodcase
//

import Foundation

/// One step of an undo, with the keys that guard it and the place it restores.
///
/// A document session applies an undo step only when no other author has written its
/// ``keys`` since the edit it undoes. Steps are as small as the keys: an override or
/// property write splits into one step per key, so a step another author contested
/// can be dropped without touching its neighbors.
///
/// A step that puts a node back — the move back of a move, the re-insert of a delete —
/// carries a ``placement``. Its index is decided when the step is applied
/// (``resolved(in:)``), anchored on a sibling, so a sibling someone else inserted in
/// the meantime does not knock the node out of place. The operation itself is an
/// ordinary ``EditOperation`` and needs no new case or wire format.
public struct GuardedInverse: Friendly {
    /// Creates a step.
    ///
    /// - Parameters:
    ///   - operation: The operation that undoes the edit.
    ///   - keys: The keys the undone edit wrote, which guard this step.
    ///   - placement: Where a restored node lands, for a move or an insert.
    public init(operation: EditOperation, keys: [ChangeKey], placement: Placement? = nil) {
        self.operation = operation
        self.keys = keys
        self.placement = placement
    }

    /// The operation that undoes the edit, with its captured index as the fallback.
    public var operation: EditOperation

    /// The keys the undone edit wrote, which guard this step.
    public var keys: [ChangeKey]

    /// Where a restored node lands, for a move or an insert; `nil` otherwise.
    public var placement: Placement?

    /// The operation to apply now, its index re-derived from ``placement``.
    ///
    /// A move or an insert takes its parent and index from the placement, resolved
    /// against the document as it stands. A step that restores one metadata entry
    /// writes that entry back onto the node's metadata as it stands, keeping every
    /// other entry. Every other operation is returned unchanged.
    ///
    /// - Parameter document: The document the step is about to be applied to.
    /// - Returns: The operation to apply.
    public func resolved(in document: EditableDocument) -> EditOperation {
        guard let placement else { return resolvedMetadataEntry(in: document) ?? operation }
        switch operation {
        case var .moveNode(move):
            move.newParentID = placement.parentID
            move.index = placement.index(placing: move.nodeID, in: document)
            return .moveNode(move)
        case var .insertNode(insert):
            insert.parentID = placement.parentID
            insert.index = placement.index(placing: insert.node.id, in: document)
            return .insertNode(insert)
        default:
            return operation
        }
    }
}
