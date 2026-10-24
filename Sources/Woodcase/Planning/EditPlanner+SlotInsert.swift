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
                placed.append(expandedID(ofInserted: settled, in: document))
            }
            try validating(operations, address: parentID ?? "", in: document)
            return StructuralEditPlan(operations: operations, placedIDs: placed)

        case let .slot(refID, slotKey, containerKey):
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
            return try finishing(session, placing: localIDs, in: slotKey, of: refID, address: parentID ?? "")
        }
    }

    /// Plans Duplicate: a copy of each node right after it, in its own parent — slot
    /// content in its slot, with fresh ids throughout, the nodes in the fills an
    /// instance among them writes included (Penumbra spec §13.5 rules 4 and 8).
    ///
    /// A copy of slot content is written into the slot's fill, the default content
    /// copied into one first when the slot shows it; a copy of a stored node is an
    /// insert after it. Penumbra's own offsets for a top-level duplicate are its own;
    /// this plans the in-place copy.
    ///
    /// ```swift
    /// let plan = try EditPlanner.planDuplicate(nodeIDs: ["Filled/Row2/ItemB"], in: document)
    /// selection = plan.placedIDs
    /// ```
    ///
    /// Refused for a node inside an instance outside its slots' content
    /// (``EditRefusal/Code/insideInstance``) and for one naming nothing
    /// (``EditRefusal/Code/addressNotFound``).
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes, by stored or expanded id; a node inside another given
    ///     goes with it.
    ///   - document: The document, as it stands.
    /// - Returns: The edits, to submit as one, and the copies' ids in the order given.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planDuplicate(nodeIDs: [String], in document: EditableDocument) throws(EditRefusal) -> StructuralEditPlan {
        let session = SlotEditSession(document: document)
        let origins = try SlotOrigin.topMost(
            nodeIDs.map { id throws(EditRefusal) in try SlotOrigin(id, in: session) }, in: session
        )
        var stored: [EditOperation] = []
        var placed: [Placed] = []
        var copied: [String?: [Int]] = [:]
        for origin in origins {
            switch origin {
            case let .document(id):
                let copy = try storedCopy(of: id, taken: &session.taken, in: document)
                let parent = document.parentID(of: id)
                let original = siblingIndex(of: id, in: document)
                let index = original + 1 + (copied[parent] ?? []).count(where: { $0 < original })
                copied[parent, default: []].append(original)
                stored.append(.insertNode(EditOperation.InsertNode(node: copy, parentID: parent, index: index)))
                placed.append(.stored(expandedID(ofInserted: copy, in: document)))
            case let .content(refID, key):
                try placed.append(duplicate(key, of: refID, in: session))
            }
        }
        let overrides = session.writeOperations()
        try validating(stored + overrides, address: nodeIDs.first ?? "", in: document)
        return StructuralEditPlan(
            operations: stored + overrides,
            placedIDs: placed.map { $0.expandedID(in: session) },
            renamedIDs: session.renamedIDs,
            materializedSlotIDs: session.materializedSlotIDs
        )
    }
}

extension EditPlanner {
    /// A node a slot plan placed, to name once the plan is done.
    enum Placed {
        /// A stored node, by its expanded id.
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

    /// The expanded id a node inserted into the document answers to: its id, and for an
    /// instance its component root's after that.
    static func expandedID(ofInserted node: PenNode, in document: EditableDocument) -> String {
        guard case let .ref(data) = node.kind, let root = document.componentRootID(of: data) else { return node.id }
        return node.id + String(NodeAddress.separator) + root
    }

    /// A copy of a stored node, every id fresh, its fills' included.
    private static func storedCopy(
        of id: String, taken: inout Set<String>, in document: EditableDocument
    ) throws(EditRefusal) -> PenNode {
        let subtree: PenNode
        do {
            subtree = try document.materializeSubtree(rootID: id)
        } catch {
            throw EditRefusal(error, address: id, in: document)
        }
        let plan = SubtreeIDPlan.regenerating(subtree, avoiding: taken)
        taken.formUnion(plan.ids)
        return SlotJSON.renumberingFills(of: plan.applied(to: subtree), taken: &taken)
    }

    /// Copies one node of slot content into its fill, right after it.
    private static func duplicate(_ key: String, of refID: String, in session: SlotEditSession) throws(EditRefusal) -> Placed {
        guard let before = session.map(of: refID), let siteIndex = before.nodes[key]?.siteIndex else {
            throw outsideSlotsRefusal(key)
        }
        let slotKey = before.sites[siteIndex].slotKey
        guard let (site, fill) = session.ensureFill(slotKey: session.current(slotKey, in: refID), in: refID),
              let map = session.map(of: refID),
              let localID = map.nodes[session.current(key, in: refID)]?.localID,
              let node = SlotJSON.node(localID, in: fill),
              let (parent, index) = SlotJSON.position(of: localID, in: fill)
        else { throw SlotMove.unreadable(key) }
        var copies: [String: String] = [:]
        let base = session.contentBase(refID: refID, slotKey: slotKey)
        let copy = SlotJSON.renumbered(.dictionary(node), oldBase: base, newBase: base, taken: &session.taken, renames: &copies)
        var list = fill
        SlotJSON.insert(copy, into: parent, at: index + 1, in: &list)
        session.setFill(list, of: site)
        return .slot(refID: refID, slotKey: slotKey, localID: SlotJSON.id(of: copy) ?? localID)
    }
}
