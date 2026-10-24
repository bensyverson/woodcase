//
//  EditPlanner+Group.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans Group or Frame Selection: wraps nodes in a new group, or in a new frame that
    /// does not lay out its children, without moving anything on the canvas.
    ///
    /// The rules are Figma's (Penumbra spec §14, the integrator's ruling of 2026-10-15):
    ///
    /// - **Only the top-most members.** A member inside another member stays where it is,
    ///   as a selection's commands act on its top-most members; it is dropped, not refused.
    /// - **The wrapper goes into the front-most member's parent, at that member's slot.**
    ///   The front-most member is the one drawn on top: the last in document order.
    ///   Members from other parents move in, and each member keeps its document order.
    /// - **Nothing moves.** Each member's `x`/`y` — and its turn and flips, when its new
    ///   parent is turned or flipped differently from its old one — is rewritten so the
    ///   quad it is drawn as on the canvas is unchanged. A member that a stack placed
    ///   becomes the wrapper's free child where it was drawn; a fill size is frozen at the
    ///   size it was drawn at.
    /// - **The wrapper is unturned in its parent** and spans the union of its members'
    ///   canvas quads, as that parent's own coordinates measure them. A group's box is that
    ///   union; a frame is placed and sized to it. In a stack, the wrapper takes the
    ///   front-most member's place in the flow (and its absolute position, if it had one).
    ///
    /// In an instance's slot content — the front-most member there — the wrapper goes into
    /// that member's parent in the fill, and the whole change is one `children` override of
    /// each slot it touches, a default content copied into a fill first (Penumbra spec
    /// §13.5 rules 4–6): ``WrapPlan/wrapperID`` is then the wrapper's expanded id, and
    /// ``WrapPlan/renamedIDs`` carries a selection across the copy.
    ///
    /// Refused inside a component instance outside its slots' content, and when the
    /// front-most member is stored but another is slot content
    /// (``EditRefusal/Code/insideInstance``); for an empty list (``EditRefusal/Code/noNodes``), for an id naming nothing
    /// (``EditRefusal/Code/addressNotFound``), and when a member moving in would make a
    /// component contain itself (``EditRefusal/Code/wouldCloseComponentLoop``, whose
    /// ``EditRefusal/detail`` is the loop).
    ///
    /// - Parameters:
    ///   - nodeIDs: The members: stored ids, or the expanded ids an editor holds (an
    ///     instance's root resolves to its `ref`).
    ///   - kind: A group, or a free frame.
    ///   - name: The wrapper's name, written with it so one undo takes both away; `nil`
    ///     leaves it unnamed.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands, which the canvas quads are read
    ///     from.
    /// - Returns: The edits, to submit as one, and the wrapper's id.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planGroup(
        nodeIDs: [String],
        kind: WrapKind,
        named name: String? = nil,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> WrapPlan {
        if let inSlot = try planSlotGroup(nodeIDs, kind: kind, named: name, in: document, layout: layout) {
            return inSlot
        }
        let members = try topMostMembers(nodeIDs, in: document)
        guard let front = members.last else {
            throw EditRefusal(code: .noNodes, address: "", message: "Select something to \(kind.verb).")
        }
        let parent = document.parentID(of: front)
        for member in members where document.parentID(of: member) != parent {
            do {
                try document.validate(.moveNode(EditOperation.MoveNode(nodeID: member, newParentID: parent)))
            } catch {
                throw EditRefusal(error, address: member, in: document)
            }
        }

        let parentMap = canvasMap(of: parent, in: document, layout: layout) ?? .identity
        let union = wrapperFrame(
            ofExpanded: members.map { document.expandedID(of: .node(id: $0)) }, under: parentMap, layout: layout
        )
        let placing: Placing = if !laysOut(parent, in: document) {
            .free
        } else if document.node(id: front)?.common.layoutPosition == .absolute {
            .absolute
        } else {
            .inFlow
        }

        let wrapperID = freshID(in: document)
        var wrapper = wrapperNode(wrapperID, kind: kind, frame: union, placing: placing)
        wrapper.common.name = name
        var operations: [EditOperation] = [
            .insertNode(EditOperation.InsertNode(
                node: wrapper, parentID: parent, index: siblingIndex(of: front, in: document)
            )),
        ]
        operations += members.map { .moveNode(EditOperation.MoveNode(nodeID: $0, newParentID: wrapperID)) }

        let wrapperMap = parentMap.concatenating(.translation(x: union.x, y: union.y))
        let flips = flipParity(of: parent, in: document)
        for member in members {
            let writes = placementWrites(
                of: member, from: document.parentID(of: member), newParentMap: wrapperMap,
                newParentFlips: flips, placing: .free, in: document, layout: layout
            )
            if !writes.isEmpty {
                operations.append(.setProperties(EditOperation.SetProperties(nodeID: member, properties: writes)))
            }
        }
        return WrapPlan(operations: operations, wrapperID: wrapperID)
    }

    // MARK: - Private

    /// The members as stored ids, each once, without any inside another, in document order.
    private static func topMostMembers(_ ids: [String], in document: EditableDocument) throws(EditRefusal) -> [String] {
        var stored: [String] = []
        for id in ids {
            let found = try restructuredID(id, in: document)
            if !stored.contains(found) { stored.append(found) }
        }
        let members = Set(stored)
        return stored
            .filter { id in !document.ancestors(of: id).contains(where: members.contains) }
            .map { (id: $0, order: orderPath(of: $0, in: document)) }
            .sorted { $0.order.lexicographicallyPrecedes($1.order) }
            .map(\.id)
    }

    /// The wrapper's frame in its parent's own coordinates: the bounds of the members'
    /// canvas quads mapped there, snapped to a millionth. A wrapper whose members are all
    /// hidden is an empty box at the front-most one's anchor.
    ///
    /// - Parameters:
    ///   - members: The members' expanded ids, front-most last.
    ///   - parentMap: The canvas map of the wrapper's parent.
    ///   - layout: The layout the quads are read from.
    internal static func wrapperFrame(ofExpanded members: [String], under parentMap: Transform, layout: PenLayoutState) -> PenRect {
        let inverse = parentMap.inverted() ?? .identity
        let placement = { (id: String) in
            PenLayoutEngine.canvasPlacement(of: id, in: layout.document, layoutRects: layout.rects)
        }
        let points = members.flatMap { placement($0)?.corners ?? [] }.map(inverse.apply(to:))
        guard !points.isEmpty else {
            let anchor = members.last.flatMap { placement($0)?.transform }
                .map { inverse.concatenating($0).apply(to: .zero) } ?? .zero
            return PenRect(x: snapped(anchor.x), y: snapped(anchor.y), width: 0, height: 0)
        }
        let minX = snapped(points.map(\.x).min() ?? 0), minY = snapped(points.map(\.y).min() ?? 0)
        let maxX = snapped(points.map(\.x).max() ?? 0), maxY = snapped(points.map(\.y).max() ?? 0)
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// A value snapped to a millionth when it is within floating-point noise of one.
    private static func snapped(_ value: Double) -> Double {
        switch number(value) {
        case let .int(whole): Double(whole)
        case let .double(fraction): fraction
        default: value
        }
    }

    /// The new wrapper: placed by its anchor unless a stack places it, with no turn.
    internal static func wrapperNode(_ id: String, kind: WrapKind, frame: PenRect, placing: Placing) -> PenNode {
        var common = PenNodeCommon()
        if placing != .inFlow {
            common.x = .literal(frame.x)
            common.y = .literal(frame.y)
        }
        if placing == .absolute {
            common.layoutPosition = .absolute
        }
        let nodeKind: PenNode.Kind = switch kind {
        case .group:
            .group(PenNode.GroupData())
        case .frame:
            .frame(PenNode.FrameData(
                width: .fixed(frame.width), height: .fixed(frame.height), layout: PenLayoutDirection.none
            ))
        }
        return PenNode(id: id, common: common, kind: nodeKind)
    }

    /// An id no node in the document holds.
    private static func freshID(in document: EditableDocument) -> String {
        var id = PenID.generate()
        while document.node(id: id) != nil {
            id = PenID.generate()
        }
        return id
    }
}

private extension WrapKind {
    /// The command, as a sentence names it.
    var verb: String {
        switch self {
        case .group: "group"
        case .frame: "frame"
        }
    }
}
