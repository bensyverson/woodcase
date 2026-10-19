//
//  EditPlanner+IntentRouting.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans an editor's intent wherever each of its properties is stored — the
    /// inspector's counterpart of ``routeWrites(_:at:in:)``.
    ///
    /// ``plan(_:at:in:)-(_,ResolvedNodeAddress,_)`` refuses a set, bind or unbind inside an
    /// instance, so nobody overrides an instance without asking (``EditIntent``). An
    /// inspector has asked: it shows the instance and marks what it overrides, so a change
    /// there means the override. This plans it as one, by the same rule
    /// ``routeWrites(_:at:in:)`` and ``NodeInspection/storage(of:)`` follow:
    ///
    /// | Intent | Stored on the node | Stored as an override |
    /// |---|---|---|
    /// | ``EditIntent/set(_:)`` | a set | an override of the values |
    /// | ``EditIntent/bind(property:variable:)`` | a bind | an override of `$name`, refused as a bind is for a missing variable or one of the wrong type |
    /// | ``EditIntent/unbind(property:)`` | an unbind | an override of the value the variable the instance shows resolves to, under the node's theme |
    ///
    /// A node with storage of its own stores everything itself; an instance root stores its
    /// `common.` properties on the `ref` node and the component root's as root overrides,
    /// so a set naming both is split; a node inside an instance stores everything as an
    /// override, and content the instance wrote into a slot is written into the slot's
    /// fill. ``EditIntent/override(_:unset:)`` and ``EditIntent/resetOverride(_:)`` already
    /// name their storage and plan as they always do.
    ///
    /// ```swift
    /// let inspection = document.inspect(expandedID: "Chip/Button")!
    /// let plan = try EditPlanner.plan(.set(["common.x": 80, "kind.fills": "#E5484D"]), routedAt: inspection.address, in: document)
    /// // [.setProperties(Chip: common.x), .overrideRoot(Chip: fill)]
    /// ```
    ///
    /// - Parameters:
    ///   - intent: What to change.
    ///   - target: The node an inspector shows.
    ///   - document: The document the plan will be applied to, as it stands.
    /// - Returns: The edits in one plan: the node's own writes first, then the overrides.
    ///   Its ``EditPlan/storage`` is ``EditPlan/Storage/instanceOverride`` when any edit is
    ///   an override; its ``EditPlan/targetID`` is the instance's `ref` node either way,
    ///   since that node stores both.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func plan(
        _ intent: EditIntent,
        routedAt target: ResolvedNodeAddress,
        in document: EditableDocument
    ) throws(EditRefusal) -> EditPlan {
        do {
            return try routedPlanning(intent, at: target, in: document)
        } catch {
            throw EditRefusal(error, address: target.address, in: document)
        }
    }
}

private extension EditPlanner {
    /// Plans an intent with each property stored where it is held, throwing the error the
    /// document or the grammar raised.
    static func routedPlanning(
        _ intent: EditIntent,
        at target: ResolvedNodeAddress,
        in document: EditableDocument
    ) throws -> EditPlan {
        let holder = Holder(target, in: document)
        let written = target.address
        switch intent {
        case let .set(properties):
            let (own, overridden) = holder.split(properties)
            var plans: [EditPlan] = []
            if !own.isEmpty || overridden.isEmpty {
                try plans.append(planning(.set(own), at: target, written: written, in: document))
            }
            if !overridden.isEmpty {
                try plans.append(planning(.override(overridden), at: target, written: written, in: document))
            }
            return joined(plans)
        case let .bind(property, variable) where holder.storage(of: property) == .instanceOverride:
            let name = variable.hasPrefix(PenDollarEscape.dollar) ? String(variable.dropFirst()) : variable
            try checkBinding(
                property, to: name,
                expecting: NodePropertyCodec.bindableVariableType(of: property),
                address: written, in: document
            )
            let reference = AnyCodable.string(PenDollarEscape.dollar + name)
            return try planning(.override([property: reference]), at: target, written: written, in: document)
        case let .unbind(property) where holder.storage(of: property) == .instanceOverride:
            let value = try unboundValue(
                of: property, on: shownNode(at: target, in: document),
                at: target, written: written, in: document
            )
            return try planning(.override([property: value]), at: target, written: written, in: document)
        case .bind, .unbind, .override, .resetOverride:
            return try planning(intent, at: target, written: written, in: document)
        }
    }

    /// The node an instance shows at an address, its overrides applied: an instance
    /// root's component root, or a node inside it.
    static func shownNode(at target: ResolvedNodeAddress, in document: EditableDocument) -> PenNode? {
        switch target {
        case let .node(id):
            try? document.expandRef(nodeID: id).expandedNode
        case let .instanceDescendant(refID, key):
            PlacedNode(descendant: key, ofInstance: refID, in: document)?.node
        }
    }

    /// Plans that store parts of one intent, as one: their edits in order, stored as an
    /// override when any of them is.
    static func joined(_ plans: [EditPlan]) -> EditPlan {
        guard var joined = plans.first else {
            preconditionFailure("an intent plans at least one part")
        }
        for plan in plans.dropFirst() {
            joined.operations += plan.operations
            joined.divergences += plan.divergences
            if plan.storage == .instanceOverride {
                joined.storage = .instanceOverride
            }
        }
        return joined
    }
}
