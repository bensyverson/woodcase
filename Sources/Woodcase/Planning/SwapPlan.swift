//
//  SwapPlan.swift
//  Woodcase
//

import Foundation

/// What ``EditPlanner/planSwap(instanceID:to:in:)`` decided a swap becomes: the edits, and
/// which of the instance's fills moved to the new component and which were dropped.
///
/// An editor names the dropped ones in the swap's notice ("The content of slot *Actions*
/// was removed"; Penumbra spec §13.5 rule 14).
///
/// ```swift
/// let plan = try EditPlanner.planSwap(instanceID: "Filled", to: "ScreenDark", in: document)
/// try session.submit(.local(LocalEdit(operations: plan.operations)))
/// if !plan.droppedSlots.isEmpty { showNotice(plan.droppedSlots) }
/// ```
public struct SwapPlan: Friendly {
    /// Creates a plan.
    ///
    /// - Parameters:
    ///   - operations: The edits, to submit as one.
    ///   - keptSlots: The names of the slots whose fills moved to the new component.
    ///   - droppedSlots: The names of the slots whose fills were dropped.
    public init(operations: [EditOperation], keptSlots: [String], droppedSlots: [String]) {
        self.operations = operations
        self.keptSlots = keptSlots
        self.droppedSlots = droppedSlots
    }

    /// The edits, to submit as one.
    public var operations: [EditOperation]

    /// The names of the slots whose fills moved to the new component's slot of the same
    /// name, in the old component's tree order.
    public var keptSlots: [String]

    /// The names of the slots whose fills were dropped, the new component having no slot
    /// of that name, in the old component's tree order.
    public var droppedSlots: [String]
}
