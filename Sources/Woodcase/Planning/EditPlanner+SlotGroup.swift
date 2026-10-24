//
//  EditPlanner+SlotGroup.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Plans Group or Frame Selection whose front-most member is in an instance's slot
    /// content: the wrapper goes into that member's parent in the fill, at its index, and
    /// every member moves in keeping the quad it is drawn as, written as one `children`
    /// override of each slot touched (Penumbra spec §13.5 rule 4, §14).
    ///
    /// - Parameters:
    ///   - nodeIDs: The members, as ``planGroup(nodeIDs:kind:named:in:layout:)`` takes them.
    ///   - kind: A group, or a free frame.
    ///   - name: The wrapper's name, or `nil` for none.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands.
    /// - Returns: The plan, or `nil` when no member is slot content — an ordinary group.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/insideInstance`` when the
    ///   front-most member is stored but another is slot content, or a member is inside an
    ///   instance outside its slots; and what the move into the wrapper refuses.
    static func planSlotGroup(
        _ nodeIDs: [String],
        kind: WrapKind,
        named name: String?,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> WrapPlan? {
        let session = SlotEditSession(document: document)
        var resolved: [SlotOrigin] = []
        for id in nodeIDs {
            try resolved.append(SlotOrigin(id, in: session))
        }
        guard resolved.contains(where: { !$0.isStored }) else { return nil }
        let order = drawOrder(of: layout)
        let members = SlotOrigin.topMost(resolved, in: session).sorted {
            (order[expandedID(of: $0, in: session)] ?? -1) < (order[expandedID(of: $1, in: session)] ?? -1)
        }
        guard case let .content(refID, frontKey)? = members.last else {
            let inside = members.first { !$0.isStored }.map { expandedID(of: $0, in: session) } ?? ""
            throw outsideSlotsRefusal(inside)
        }
        guard let map = session.map(of: refID), let front = map.nodes[frontKey], let site = front.siteIndex,
              let parentKey = front.parentKey, let parent = map.nodes[parentKey]
        else { throw outsideSlotsRefusal(refID + String(NodeAddress.separator) + frontKey) }

        let slotKey = map.sites[site].slotKey
        let parentID = map.expandedID(of: parentKey)
        let parentMap = PenLayoutEngine.canvasPlacement(of: parentID, in: layout.document, layoutRects: layout.rects)?
            .transform ?? .identity
        let union = wrapperFrame(ofExpanded: members.map { expandedID(of: $0, in: session) }, under: parentMap, layout: layout)
        let placing: Placing = if !SlotMove.laysOut(parent.node) {
            .free
        } else if front.node.common.layoutPosition == .absolute {
            .absolute
        } else {
            .inFlow
        }
        let wrapperID = PenID.generate(avoiding: session.taken)
        session.taken.insert(wrapperID)
        var wrapper = wrapperNode(wrapperID, kind: kind, frame: union, placing: placing)
        wrapper.common.name = name
        let json: AnyCodable
        do {
            json = try SlotJSON.json(of: wrapper)
        } catch {
            throw EditRefusal(error, address: nodeIDs.first ?? "", in: document)
        }
        let contentPrefix = map.sites[site].contentPrefix
        var move = SlotMove(
            session: session,
            destination: .slot(refID: refID, slotKey: slotKey, containerKey: contentPrefix + wrapperID),
            layout: layout
        )
        move.wrapper = SlotMove.Wrapper(
            json: json, refID: refID, slotKey: slotKey,
            containerKey: parentKey == slotKey ? nil : parentKey,
            index: parent.node.kind.inlineChildren.firstIndex { $0.id == front.node.id }
        )
        move.fixedTarget = SlotMove.TargetGeometry(
            map: parentMap.concatenating(.translation(x: union.x, y: union.y)),
            flips: SlotMove.flipParity(ofExpanded: parentID, in: layout),
            laysOut: false
        )
        let plan = try move.plan(members, at: nil, keepingDrawnPlace: .zero, snapping: .none)
        return WrapPlan(
            operations: plan.operations,
            wrapperID: Placed.slot(refID: refID, slotKey: slotKey, localID: wrapperID).expandedID(in: session),
            renamedIDs: plan.renamedIDs,
            materializedSlotIDs: plan.materializedSlotIDs
        )
    }

    /// The expanded id a member answers to as the layout draws it.
    private static func expandedID(of origin: SlotOrigin, in session: SlotEditSession) -> String {
        switch origin {
        case let .document(id):
            session.document.expandedID(of: .node(id: id))
        case let .content(refID, key):
            session.map(of: refID)?.expandedID(of: key) ?? refID + String(NodeAddress.separator) + key
        }
    }

    /// Each node of the drawn document by its place in document order: a later one is
    /// drawn on top of an earlier one.
    private static func drawOrder(of layout: PenLayoutState) -> [String: Int] {
        var order: [String: Int] = [:]
        var pending = Array(layout.document.children.reversed())
        while let node = pending.popLast() {
            order[node.id] = order.count
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return order
    }
}
