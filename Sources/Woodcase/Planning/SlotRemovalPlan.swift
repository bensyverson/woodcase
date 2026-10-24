//
//  SlotRemovalPlan.swift
//  Woodcase
//

import Foundation

/// What ``EditPlanner/planRemoveSlot(frameID:in:)`` decided Remove Slot becomes: the
/// edits, and the instances whose fills they clear.
///
/// An editor asks first when ``filledInstanceIDs`` is not empty — "3 instances fill
/// *Actions*. Their content will be removed." (Penumbra spec §13.5 rule 10) — and
/// submits ``operations`` as one edit when the designer chooses Remove.
///
/// ```swift
/// let plan = try EditPlanner.planRemoveSlot(frameID: "Actions", in: document)
/// plan.filledInstanceIDs.count   // 3
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// ```
public struct SlotRemovalPlan: Friendly {
    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - operations: The edits, to submit as one.
    ///   - filledInstanceIDs: The expanded root ids of the instances whose fill of the
    ///     slot the edits clear.
    public init(operations: [EditOperation], filledInstanceIDs: [String]) {
        self.operations = operations
        self.filledInstanceIDs = filledInstanceIDs
    }

    /// The edits: the frame stops being a slot, and every fill of it in this document is
    /// removed.
    public var operations: [EditOperation]

    /// The expanded root ids of the instances in this document that fill the slot — an
    /// empty fill included — sorted. Instances in other documents keep their fills.
    public var filledInstanceIDs: [String]
}
