//
//  NodeInspection+Storage.swift
//  Woodcase
//

import Foundation

public extension NodeInspection {
    /// Where a write of a property of this node is stored — the same answer
    /// ``EditPlanner/plan(_:routedAt:in:)`` and ``EditPlanner/routeWrites(_:at:in:)`` act on.
    ///
    /// An inspector reads a value where it would write one: for
    /// ``EditPlan/Storage/instanceOverride``, the instance's override when it stores one
    /// (``overrides``) and ``sourceNode``'s value otherwise; for ``EditPlan/Storage/node``,
    /// the node's own storage — the `ref` node's, for an instance root's `common.`
    /// properties, where a root override of the same name would mean nothing. Content an
    /// instance wrote into a slot is ``EditPlan/Storage/instanceOverride``: the planner
    /// writes it into the slot's fill, and it carries no overrides of its own, so a read
    /// falls through to ``sourceNode``.
    ///
    /// ```swift
    /// let inspection = document.inspect(expandedID: "Chip/Button")!
    /// inspection.storage(of: "common.x")    // .node: the ref node's own
    /// inspection.storage(of: "kind.fills")  // .instanceOverride: a root override
    /// ```
    ///
    /// - Parameter property: A property path (`common.x`, `kind.fills`).
    /// - Returns: Where a write of it is stored.
    func storage(of property: String) -> EditPlan.Storage {
        EditPlanner.Holder(source).storage(of: property)
    }
}
