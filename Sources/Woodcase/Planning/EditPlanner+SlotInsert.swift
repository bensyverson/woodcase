//
//  EditPlanner+SlotInsert.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans inserting nodes — a creation tool's new layer, a paste — into a stored parent,
    /// the canvas, or an instance's slot.
    ///
    /// Into a slot, the nodes join its fill: one `children` override of the slot, the
    /// default content copied into a fill first when the slot shows it (Penumbra spec
    /// §13.5 rules 4–6). Anywhere, a node keeps its ids when no node in the document has
    /// them — the nodes in every fill included — and takes fresh ones, the whole subtree,
    /// when one does, since Pen renames a repeated id on load and a path to it stops
    /// resolving; the fills an instance among them writes are renumbered the same way.
    /// ``StructuralEditPlan/placedIDs`` names the nodes as they will answer.
    ///
    /// ```swift
    /// // The + button's "Item B": an instance added at the end of the slot.
    /// let item = PenNode(id: "", common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: "ItemB")))
    /// let plan = try EditPlanner.planInsert([item], into: "Filled/List", in: document)
    /// ```
    ///
    /// Refused for a parent inside an instance outside its slots
    /// (``EditRefusal/Code/insideInstance``), for one naming nothing
    /// (``EditRefusal/Code/addressNotFound``), and for an insert that would make a
    /// component contain itself (``EditRefusal/Code/wouldCloseComponentLoop``).
    ///
    /// - Parameters:
    ///   - nodes: The nodes, each with its children inline. An empty id is drawn.
    ///   - parentID: A stored id, a slot's or a slot content container's expanded id, or
    ///     `nil` for the canvas.
    ///   - index: Where the first goes among the parent's children, the rest after it;
    ///     `nil` puts them last.
    ///   - document: The document, as it stands.
    /// - Returns: The edits, to submit as one, and where the nodes answer afterward.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planInsert(
        _ nodes: [PenNode],
        into parentID: String?,
        at index: Int? = nil,
        in document: EditableDocument
    ) throws(EditRefusal) -> StructuralEditPlan {
        try planInsert(nodes, into: parentID, at: index, reserving: [], in: document).plan
    }
}

extension EditPlanner {
    /// ``planInsert(_:into:at:in:)`` with ids reserved for other nodes the caller writes in
    /// the same edit — a paste's definitions and connectors — so a default content copied
    /// into a fill never takes one.
    ///
    /// - Parameters:
    ///   - nodes: The nodes, each with its children inline.
    ///   - parentID: A stored id, a slot's or a slot content container's expanded id, or
    ///     `nil` for the canvas.
    ///   - index: Where the first goes among the parent's children; `nil` puts them last.
    ///   - reserving: Ids no copy of default content may take.
    ///   - document: The document, as it stands.
    /// - Returns: The plan, and for a slot the expanded-id prefix of its content after the
    ///   plan (`Filled/`); `nil` outside slots.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planInsert(
        _ nodes: [PenNode],
        into parentID: String?,
        at index: Int?,
        reserving: Set<String>,
        in document: EditableDocument
    ) throws(EditRefusal) -> (plan: StructuralEditPlan, contentBase: String?) {
        let session = SlotEditSession(document: document)
        let destination = try SlotDestination(parentID, in: session)
        var renames: [String: String] = [:]
        switch destination {
        case let .document(parent):
            var operations: [EditOperation] = []
            var placed: [String] = []
            for (step, node) in nodes.enumerated() {
                let settled = SlotJSON.settlingIDs(of: node, taken: &session.taken)
                operations.append(.insertNode(EditOperation.InsertNode(
                    node: settled, parentID: parent, index: index.map { $0 + step }
                )))
                placed.append(settled.id)
            }
            try validating(operations, address: parentID ?? "", in: document)
            return (StructuralEditPlan(operations: operations, placedIDs: placed), nil)

        case let .slot(refID, slotKey, containerKey):
            session.taken.formUnion(reserving)
            var localIDs: [String] = []
            for (step, node) in nodes.enumerated() {
                let base = session.contentBase(refID: refID, slotKey: slotKey)
                let json: AnyCodable
                do {
                    json = try SlotJSON.json(of: node)
                } catch {
                    throw EditRefusal(error, address: parentID ?? "", in: document)
                }
                let kept = SlotJSON.keepingIDs(json, base: base, taken: &session.taken, renames: &renames)
                guard session.insert(
                    kept, refID: refID, slotKey: slotKey, containerKey: containerKey, at: index.map { $0 + step }
                ) else { throw SlotMove.unreadable(parentID ?? slotKey) }
                localIDs.append(SlotJSON.id(of: kept) ?? node.id)
            }
            let plan = try finishing(session, placing: localIDs, in: slotKey, of: refID, address: parentID ?? "")
            return (plan, session.contentBase(refID: refID, slotKey: slotKey))
        }
    }
}

extension EditPlanner {
    /// A node a slot plan placed, to name once the plan is done.
    enum Placed {
        /// A stored node, by its own id — what an editor selects it by, an instance
        /// among them.
        case stored(String)

        /// A node in a slot's fill, by its id there.
        case slot(refID: String, slotKey: String, localID: String)

        /// The expanded id it answers to after the plan.
        func expandedID(in session: SlotEditSession) -> String {
            switch self {
            case let .stored(id):
                return id
            case let .slot(refID, slotKey, localID):
                guard let map = session.map(of: refID),
                      let site = map.site(slotKey: session.current(slotKey, in: refID))
                else { return refID + String(NodeAddress.separator) + localID }
                return map.expandedID(of: map.sites[site].contentPrefix + localID)
            }
        }
    }

    /// The plan for a session's rewrite of one slot, the placed nodes named.
    static func finishing(
        _ session: SlotEditSession,
        placing localIDs: [String],
        in slotKey: String,
        of refID: String,
        address: String
    ) throws(EditRefusal) -> StructuralEditPlan {
        let operations = session.writeOperations()
        try validating(operations, address: address, in: session.document)
        return StructuralEditPlan(
            operations: operations,
            placedIDs: localIDs.map { Placed.slot(refID: refID, slotKey: slotKey, localID: $0).expandedID(in: session) },
            renamedIDs: session.renamedIDs,
            materializedSlotIDs: session.materializedSlotIDs
        )
    }

    /// Runs the document's own checks on planned edits — the loop guard among them.
    static func validating(
        _ operations: [EditOperation], address: String, in document: EditableDocument
    ) throws(EditRefusal) {
        do {
            for operation in operations {
                try document.validate(operation)
            }
        } catch {
            throw EditRefusal(error, address: address, in: document)
        }
    }
}
