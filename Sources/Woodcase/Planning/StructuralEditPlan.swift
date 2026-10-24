//
//  StructuralEditPlan.swift
//  Woodcase
//

import Foundation

/// What a structural edit that can reach into slots becomes: the edits to submit as one,
/// and where the nodes it placed now answer.
///
/// A move, insert, duplicate or fill intent aimed at an instance's slot writes that slot's
/// whole content as one `children` override of the slot frame (its **fill**); the nodes
/// in it have no storage of their own and answer to expanded ids (`<instance>/<id>`).
/// The first structural change on a slot that still shows its component's default
/// content copies that content into a fill first, with fresh ids, so a node of it that
/// an editor had selected answers to a new id afterward: ``renamedIDs`` and
/// ``renamed(_:)`` carry the selection across.
///
/// ```swift
/// let plan = try EditPlanner.planMove(
///     nodeIDs: ["Filled/Row3"], into: "Filled/List", at: 0, in: document, layout: layout
/// )
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// selection = plan.placedIDs   // ["Filled/Row3"]
/// ```
public struct StructuralEditPlan: Friendly {
    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - operations: The edits to apply, in order, as one.
    ///   - placedIDs: The expanded ids the moved, inserted or copied nodes answer to
    ///     after the edit, in the order they were asked for.
    ///   - renamedIDs: Expanded id before → after, for every node of default content the
    ///     edit copied into a fill.
    ///   - materializedSlotIDs: The slot frames whose default content became a fill.
    public init(
        operations: [EditOperation],
        placedIDs: [String] = [],
        renamedIDs: [String: String] = [:],
        materializedSlotIDs: [String] = []
    ) {
        self.operations = operations
        self.placedIDs = placedIDs
        self.renamedIDs = renamedIDs
        self.materializedSlotIDs = materializedSlotIDs
    }

    /// The edits to apply, in order. Submit them as one edit, so one undo reverts the
    /// whole change — a default content copied into a fill included.
    public var operations: [EditOperation]

    /// The expanded ids the nodes the edit placed answer to after it, in the order they
    /// were asked for: a moved node's new id (a node moved from a stored parent into a
    /// slot keeps its own id behind the instance's), an inserted or copied node's id.
    /// Empty for an edit that places nothing (a delete, Empty Slot, Reset Slot).
    public var placedIDs: [String]

    /// Expanded id before the edit → after it, for each node of a slot's default content
    /// the edit copied into a fill, and each node inside an instance among them.
    public var renamedIDs: [String: String]

    /// The expanded ids of the slot frames whose default content this edit copied into
    /// a fill (Penumbra spec §13.5 rule 6).
    public var materializedSlotIDs: [String]

    /// The id a node answers to after the edit: its renamed id when the edit copied it
    /// into a fill, or a node inside an instance it copied, else the id as given.
    ///
    /// - Parameter id: An expanded id from before the edit.
    /// - Returns: The id the same node answers to after it.
    public func renamed(_ id: String) -> String {
        if let exact = renamedIDs[id] { return exact }
        let separator = String(NodeAddress.separator)
        var steps = id.split(separator: NodeAddress.separator).map(String.init)
        var tail: [String] = []
        while steps.count > 1 {
            tail.insert(steps.removeLast(), at: 0)
            if let prefix = renamedIDs[steps.joined(separator: separator)] {
                return ([prefix] + tail).joined(separator: separator)
            }
        }
        return id
    }
}
