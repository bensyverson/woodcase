//
//  EditPlan.swift
//  Woodcase
//

import Foundation

/// What ``EditPlanner`` decided an ``EditIntent`` becomes: the edits to submit, where
/// they are stored, and what the result will say about itself.
///
/// Planning never mutates. A caller submits ``operations`` through its
/// ``DocumentSession`` — guarding ``targetID``'s revision if it holds one — and shows
/// ``divergences`` to whoever asked.
///
/// ```swift
/// let plan = try EditPlanner.plan(.set(["common.opacity": 0.5]), at: address, in: document)
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// ```
public struct EditPlan: Friendly {
    /// Where a plan's edits are stored.
    ///
    /// The fact an editor shows ("overridden in this instance") and a CLI reports
    /// (the answer names the instance), named once rather than inferred from the
    /// operations.
    public enum Storage: String, Friendly, CaseIterable {
        /// On the addressed node itself: a `setProperties`.
        case node

        /// In a component instance's overrides: its `descendants` map, its root
        /// overrides, or a slot fill it wrote.
        case instanceOverride
    }

    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - operations: The edits to apply, in order.
    ///   - targetID: The node whose storage the edits change.
    ///   - storage: Where the edits are stored.
    ///   - divergences: How the result will differ from the intent as written.
    public init(
        operations: [EditOperation],
        targetID: String,
        storage: Storage,
        divergences: [WriteDivergence] = []
    ) {
        self.operations = operations
        self.targetID = targetID
        self.storage = storage
        self.divergences = divergences
    }

    /// The edits to apply, in order.
    public var operations: [EditOperation]

    /// The node whose storage the edits change: the addressed node for
    /// ``Storage/node``, the instance's `ref` node for ``Storage/instanceOverride``.
    ///
    /// This is the node a revision guard pins and the node a report names.
    public var targetID: String

    /// Where the edits are stored.
    public var storage: Storage

    /// How the result will differ from the intent as written; empty for the ordinary
    /// write.
    public var divergences: [WriteDivergence]
}
