//
//  WrapPlan.swift
//  Woodcase
//

import Foundation

/// What ``EditPlanner/planGroup(nodeIDs:kind:in:layout:)`` decided: the edits that wrap
/// the members, and the wrapper they make.
///
/// Planning never mutates. A caller submits ``operations`` as one edit — one undo step —
/// and selects ``wrapperID``.
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
    public init(operations: [EditOperation], wrapperID: String) {
        self.operations = operations
        self.wrapperID = wrapperID
    }

    /// The edits to apply, in order: the wrapper's insert, each member's move into it,
    /// then each member's new placement.
    public var operations: [EditOperation]

    /// The id of the group or frame the edits insert.
    public var wrapperID: String
}
