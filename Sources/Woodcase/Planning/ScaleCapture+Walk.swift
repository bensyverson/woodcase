//
//  ScaleCapture+Walk.swift
//  Woodcase
//

import Foundation

/// Capturing a selection: its top-most members, their union and every node they draw.
extension ScaleCapture {
    /// A member as named: its expanded id and where its edits are stored.
    struct Member {
        /// The id in the expanded document.
        var expandedID: String

        /// Where its edits are stored.
        var address: ResolvedNodeAddress
    }

    /// The named nodes that are not inside another named node, each once, in the order given.
    static func topMostMembers(
        _ ids: [String], in document: EditableDocument, layout: PenLayoutState
    ) throws(EditRefusal) -> [Member] {
        var members: [Member] = []
        for id in ids {
            let member: Member
            if document.node(id: id) != nil {
                member = Member(expandedID: document.expandedID(of: .node(id: id)), address: .node(id: id))
            } else if let address = document.resolve(expandedID: id) {
                member = Member(expandedID: id, address: address)
            } else {
                throw EditRefusal(
                    code: .addressNotFound, address: id, message: "No node has the id \(id); nothing was scaled."
                )
            }
            if !members.contains(where: { $0.expandedID == member.expandedID }) { members.append(member) }
        }
        let named = Set(members.map(\.expandedID))
        return members.filter { member in !layout.index.ancestors(of: member.expandedID).contains(where: named.contains) }
    }

    /// The bounds of the members' canvas quads, or an empty box at the origin.
    static func union(of ids: [String], in layout: PenLayoutState) -> PenRect {
        let boxes = ids.compactMap {
            PenLayoutEngine.canvasPlacement(of: $0, in: layout.document, layoutRects: layout.rects)?.bounds
        }
        guard var minX = boxes.first?.x, var minY = boxes.first?.y else {
            return PenRect(x: 0, y: 0, width: 0, height: 0)
        }
        var maxX = minX
        var maxY = minY
        for box in boxes {
            minX = min(minX, box.x)
            minY = min(minY, box.y)
            maxX = max(maxX, box.x + box.width)
            maxY = max(maxY, box.y + box.height)
        }
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Every node one member draws, the member first, walked from a work list.
    static func entries(for member: Member, in document: EditableDocument, layout: PenLayoutState) -> [Entry] {
        guard let drawn = drawnSubtree(of: member, in: document) else { return [] }
        var entries: [Entry] = []
        var pending: [(node: PenNode, address: ResolvedNodeAddress?, position: Entry.Position)] = [
            (drawn, member.address, memberPosition(of: member, in: document, layout: layout)),
        ]
        while let (node, address, position) = pending.popLast() {
            if let address {
                entries.append(Entry(
                    expandedID: node.id, address: address, values: Entry.values(of: node, position: position),
                    position: position
                ))
            }
            let placesChildren = EditPlanner.lays(outChildrenOf: node)
            for child in (node.kind.inlineChildrenIfPresent ?? []).reversed() {
                let placed = placesChildren && child.common.layoutPosition != .absolute
                pending.append((child, Self.address(ofDrawn: child.id, in: document), placed ? .kept : .scaled))
            }
        }
        return entries
    }

    /// Where the edits of a node of the expanded document are stored: a stored node's own
    /// id, or what ``EditableDocument/resolve(expandedID:)`` says — `nil` when nothing can
    /// store them.
    private static func address(ofDrawn id: String, in document: EditableDocument) -> ResolvedNodeAddress? {
        id.contains(NodeAddress.separator) ? document.resolve(expandedID: id) : .node(id: id)
    }

    /// The member's subtree as drawn: refs expanded, overrides applied, variables kept.
    private static func drawnSubtree(of member: Member, in document: EditableDocument) -> PenNode? {
        let root: PenNode? = switch member.address {
        case let .node(id): try? document.expandSubtree(rootID: id).0
        case let .instanceDescendant(refID, _): try? document.expandRef(nodeID: refID).expandedNode
        }
        guard let root else { return nil }
        var pending = [root]
        while let node = pending.popLast() {
            if node.id == member.expandedID { return node }
            pending += node.kind.inlineChildrenIfPresent ?? []
        }
        return nil
    }

    /// How a member moves: about the anchor, in its parent's coordinates, unless its
    /// parent's layout places it or its parent is placed nowhere.
    private static func memberPosition(
        of member: Member, in document: EditableDocument, layout: PenLayoutState
    ) -> Entry.Position {
        let placed: EditPlanner.PlacedNode? = switch member.address {
        case let .node(id): EditPlanner.PlacedNode(node: id, in: document)
        case let .instanceDescendant(refID, key): EditPlanner.PlacedNode(descendant: key, ofInstance: refID, in: document)
        }
        guard let placed else { return .kept }
        if let parent = placed.parent, EditPlanner.lays(outChildrenOf: parent),
           placed.node.common.layoutPosition != .absolute
        {
            return .kept
        }
        guard let parentID = layout.index[member.expandedID]?.parent else {
            return .anchored(canvasToParent: .identity)
        }
        guard let parentMap = PenLayoutEngine.canvasPlacement(
            of: parentID, in: layout.document, layoutRects: layout.rects
        )?.transform, let inverse = parentMap.inverted() else { return .kept }
        return .anchored(canvasToParent: inverse)
    }
}
