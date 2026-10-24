//
//  WrapPlan.swift
//  Woodcase
//

import Foundation

/// What ``EditPlanner/planGroup(nodeIDs:kind:named:in:layout:)`` decided: the edits that wrap
/// the members, and the wrapper they make.
///
/// Planning never mutates. A caller submits ``operations`` as one edit — one undo step —
/// and selects ``wrapperID``. A wrapper in an instance's slot content is written as one
/// `children` override of the slot, so no operation inserts it; ``renamed(_:)`` carries a
/// selection across the default content's first copy.
///
/// ```swift
/// let plan = try EditPlanner.planGroup(nodeIDs: ["a", "b"], kind: .group, in: document, layout: layout)
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// selection = [plan.wrapperID]
/// ```
public struct WrapPlan: Friendly {
    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - operations: The edits to apply, in order.
    ///   - wrapperID: The id of the group or frame the edits insert.
    ///   - renamedIDs: Expanded id before → after, for every node of a slot's default
    ///     content the edit copied into a fill.
    ///   - materializedSlotIDs: The slot frames whose default content became a fill.
    public init(
        operations: [EditOperation],
        wrapperID: String,
        renamedIDs: [String: String] = [:],
        materializedSlotIDs: [String] = []
    ) {
        self.operations = operations
        self.wrapperID = wrapperID
        self.renamedIDs = renamedIDs
        self.materializedSlotIDs = materializedSlotIDs
    }

    /// The edits to apply, in order: the wrapper's insert, each member's move into it,
    /// then each member's new placement.
    public var operations: [EditOperation]

    /// The id of the group or frame the edits insert: a stored id, or for a wrapper in an
    /// instance's slot content the expanded id it answers to (`Filled/k3Fq9`).
    public var wrapperID: String

    /// Expanded id before the edit → after it, for each node of a slot's default content
    /// the edit copied into a fill (Penumbra spec §13.5 rule 6); empty outside slots.
    public var renamedIDs: [String: String]

    /// The expanded ids of the slot frames whose default content this edit copied into a
    /// fill.
    public var materializedSlotIDs: [String]

    /// The id a node answers to after the edit, as ``StructuralEditPlan/renamed(_:)``
    /// reads it.
    ///
    /// - Parameter id: An expanded id from before the edit.
    /// - Returns: The id the same node answers to after it.
    public func renamed(_ id: String) -> String {
        StructuralEditPlan(operations: [], renamedIDs: renamedIDs).renamed(id)
    }
}
