//
//  EditPlanner+SlotUngroup.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans Ungroup on several groups or frames at once — stored ones, and ones in an
    /// instance's slot content — without moving anything on the canvas.
    ///
    /// Each stored group is planned as ``planUngroup(groupID:in:layout:)`` plans it, front
    /// to back, so each plan's indices still hold when it runs. A group in a slot's
    /// content is taken apart in its fill the same way — its children go to its parent at
    /// its index, each keeping the quad it is drawn as, joining the flow of a parent that
    /// lays out its children — and every slot touched is written as **one `children`
    /// override**, however many groups it held (Penumbra spec §13.5 rule 4, §14). The
    /// first structural change on a slot that still shows its default content copies
    /// that content into a fill first (rule 6). A connector attached to a group in a slot
    /// is deleted with it, in the same edit; one attached to a child stays.
    ///
    /// The one-group ``planUngroup(groupID:in:layout:)`` still refuses slot content, so a
    /// caller that plans group by group and concatenates can never write a slot from a
    /// stale copy; take several groups apart through this.
    ///
    /// ```swift
    /// let plan = try EditPlanner.planUngroup(groupIDs: ["Filled/Group1"], in: document, layout: layout)
    /// try session.submit(.local(LocalEdit(operations: plan.operations)))
    /// selection = Set(plan.placedIDs)
    /// ```
    ///
    /// Refused as ``planUngroup(groupID:in:layout:)`` refuses each group, and for a node
    /// inside an instance outside its slots' content (``EditRefusal/Code/insideInstance``).
    ///
    /// - Parameters:
    ///   - groupIDs: The groups or frames: stored ids, or the expanded ids an editor holds.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands, which the canvas quads are read
    ///     from.
    /// - Returns: The edits, to submit as one, and the children's ids afterward, group by
    ///   group in the order given.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planUngroup(
        groupIDs: [String],
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> StructuralEditPlan {
        let session = SlotEditSession(document: document)
        var stored: [String] = []
        var inSlots: [SlotUngroup] = []
        var order: [String] = []
        for id in groupIDs {
            switch try session.place(of: id) {
            case let .stored(found):
                let group = try restructuredID(found, in: document)
                guard !order.contains(group) else { continue }
                stored.append(group)
                order.append(group)
            case let .inInstance(refID, key):
                let group = try SlotUngroup(id, refID: refID, key: key, in: session, layout: layout)
                guard !order.contains(group.path) else { continue }
                inSlots.append(group)
                order.append(group.path)
            }
        }

        var operations: [EditOperation] = []
        var placed: [String: [Placed]] = [:]
        let frontToBack = stored.sorted { lhs, rhs in
            orderPath(of: rhs, in: document).lexicographicallyPrecedes(orderPath(of: lhs, in: document))
        }
        for group in frontToBack {
            operations += try planUngroup(groupID: group, in: document, layout: layout)
            placed[group] = document.childIDs(of: group).map { .stored($0) }
        }
        var connectors: [String] = []
        for group in inSlots {
            let attached = connectorIDs(attachedTo: [group.localID], in: document).filter { !connectors.contains($0) }
            connectors += attached
            session.deletedConnectorIDs.formUnion(attached)
            placed[group.path] = try group.apply(in: session)
        }
        let deletes = connectors.map { EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: $0)) }
        let overrides = session.writeOperations()
        try validating(overrides, address: groupIDs.first ?? "", in: document)
        return StructuralEditPlan(
            operations: deletes + operations + overrides,
            placedIDs: order.flatMap { placed[$0] ?? [] }.map { $0.expandedID(in: session) },
            renamedIDs: session.renamedIDs,
            materializedSlotIDs: session.materializedSlotIDs
        )
    }
}

/// One group or frame in a slot's content that Ungroup takes apart: what the layout drew,
/// read before any default content is copied into a fill, and the take-apart itself.
private struct SlotUngroup {
    /// The outermost instance.
    var refID: String

    /// The group's key, as it was before the plan renamed anything.
    var key: String

    /// The group's id in its fill or component, as the document holds it now.
    var localID: String

    /// The key of the slot whose content holds it.
    var slotKey: String

    /// The placement writes that keep each child drawn where it is, in child order.
    var writes: [[String: AnyCodable]]

    /// The instance and the key, as one path: what tells two groups apart.
    var path: String {
        refID + String(NodeAddress.separator) + key
    }

    /// Reads a group from the layout.
    ///
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/insideInstance`` for a node
    ///   outside the instance's slots' content, or ``EditRefusal/Code/notAGroup``.
    init(
        _ id: String, refID: String, key: String, in session: SlotEditSession, layout: PenLayoutState
    ) throws(EditRefusal) {
        guard let map = session.map(of: refID), let entry = map.nodes[key], let site = entry.siteIndex,
              let parentKey = entry.parentKey, let parent = map.nodes[parentKey]
        else { throw EditPlanner.outsideSlotsRefusal(id) }
        switch entry.node.kind {
        case .group, .frame:
            break
        default:
            throw EditRefusal(
                code: .notAGroup, address: id, message: "\(id) is not a group or a frame, so there is nothing to ungroup."
            )
        }
        self.refID = refID
        self.key = key
        localID = entry.localID
        slotKey = map.sites[site].slotKey

        let groupID = map.expandedID(of: key)
        let parentID = map.expandedID(of: parentKey)
        let placing: EditPlanner.Placing = if !SlotMove.laysOut(parent.node) {
            .free
        } else if entry.node.common.layoutPosition == .absolute {
            .absolute
        } else {
            .inFlow
        }
        let canvas = { (expanded: String) in
            PenLayoutEngine.canvasPlacement(of: expanded, in: layout.document, layoutRects: layout.rects)?.transform
        }
        let parentMap = canvas(parentID) ?? .identity
        let parentFlips = SlotMove.flipParity(ofExpanded: parentID, in: layout)
        let groupMap = canvas(groupID)
        let groupFlips = SlotMove.flipParity(ofExpanded: groupID, in: layout)
        let prefix = refID + String(NodeAddress.separator)
        writes = entry.node.kind.inlineChildren.map { child in
            let childKey = String(child.id.dropFirst(prefix.count))
            let expanded = map.expandedID(of: childKey)
            guard let node = map.nodes[childKey]?.node, let drawn = canvas(expanded), let groupMap else { return [:] }
            let subject = EditPlanner.PlacementSubject(
                node: node, drawn: drawn, drawnSize: layout.rects[expanded]?.drawnSize,
                oldParentMap: groupMap, oldParentFlips: groupFlips
            )
            return EditPlanner.placementWrites(
                of: subject, newParentMap: parentMap, newParentFlips: parentFlips, placing: placing
            )
        }
    }

    /// Takes the group apart in its fill: its children, re-placed, into its parent at its
    /// index, and the group gone.
    ///
    /// - Returns: The children, where they landed.
    func apply(in session: SlotEditSession) throws(EditRefusal) -> [EditPlanner.Placed] {
        guard let (site, fill) = session.ensureFill(slotKey: session.current(slotKey, in: refID), in: refID),
              let map = session.map(of: refID),
              let current = map.nodes[session.current(key, in: refID)]?.localID,
              let (parent, index) = SlotJSON.position(of: current, in: fill)
        else { throw SlotMove.unreadable(key) }
        var list = fill
        guard case let .dictionary(group)? = SlotJSON.remove(current, from: &list) else { throw SlotMove.unreadable(key) }
        let children = SlotJSON.children(of: group) ?? []
        var placed: [EditPlanner.Placed] = []
        for (offset, child) in children.enumerated() {
            let moved = try SlotMove.patched(
                child, with: offset < writes.count ? writes[offset] : [:], address: key, in: session.document
            )
            SlotJSON.insert(moved, into: parent, at: index + offset, in: &list)
            if let id = SlotJSON.id(of: moved) {
                placed.append(.slot(refID: refID, slotKey: slotKey, localID: id))
            }
        }
        session.setFill(list, of: site)
        return placed
    }
}
