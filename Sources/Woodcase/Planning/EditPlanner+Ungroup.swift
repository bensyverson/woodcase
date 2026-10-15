//
//  EditPlanner+Ungroup.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans Ungroup: takes a group's or a frame's children out into its parent and
    /// removes it, without moving anything on the canvas.
    ///
    /// The children go to the group's parent at the group's index, in their order (Penumbra
    /// spec §14, the integrator's ruling of 2026-10-15). The group's position, turn and
    /// flips are folded into each child's own, so each keeps the quad it is drawn as; a
    /// child a stack placed — ungrouping a stack frame — is freed where it was drawn, and a
    /// fill size is frozen at the size it was drawn at. In a parent that lays out its
    /// children, they join the flow at the group's index instead (their `x`/`y` removed),
    /// unless the group was absolutely positioned there, when each child is too.
    /// Ungrouping a frame works the same, and its own fills, strokes and clip go with it.
    ///
    /// Refused for a node that is neither a group nor a frame
    /// (``EditRefusal/Code/notAGroup``), inside a component instance
    /// (``EditRefusal/Code/insideInstance``), for an id naming nothing
    /// (``EditRefusal/Code/addressNotFound``), and for a component that has instances
    /// (``EditRefusal/Code/documentRefused``).
    ///
    /// - Parameters:
    ///   - groupID: The group or frame: a stored id, or the expanded id an editor holds.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands, which the canvas quads are read
    ///     from.
    /// - Returns: The edits, to submit as one. The children keep their ids.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planUngroup(
        groupID: String,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> [EditOperation] {
        let group = try restructuredID(groupID, in: document)
        guard let node = document.node(id: group), node.kind.isUngroupable else {
            throw EditRefusal(
                code: .notAGroup,
                address: groupID,
                message: "\(groupID) is not a group or a frame, so there is nothing to ungroup."
            )
        }
        let delete = EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: group))
        do {
            try document.validate(delete)
        } catch {
            throw EditRefusal(error, address: groupID, in: document)
        }

        let parent = document.parentID(of: group)
        let index = siblingIndex(of: group, in: document)
        let children = document.childIDs(of: group)
        let placing: Placing = if !laysOut(parent, in: document) {
            .free
        } else if node.common.layoutPosition == .absolute {
            .absolute
        } else {
            .inFlow
        }

        var operations: [EditOperation] = children.enumerated().map { offset, child in
            .moveNode(EditOperation.MoveNode(nodeID: child, newParentID: parent, index: index + offset))
        }
        operations.append(delete)

        let parentMap = canvasMap(of: parent, in: document, layout: layout) ?? .identity
        let flips = flipParity(of: parent, in: document)
        for child in children {
            let writes = placementWrites(
                of: child, from: group, newParentMap: parentMap, newParentFlips: flips,
                placing: placing, in: document, layout: layout
            )
            if !writes.isEmpty {
                operations.append(.setProperties(EditOperation.SetProperties(nodeID: child, properties: writes)))
            }
        }
        return operations
    }
}

private extension PenNode.Kind {
    /// Whether Ungroup takes this node apart: a group or a frame.
    var isUngroupable: Bool {
        switch self {
        case .group, .frame: true
        default: false
        }
    }
}
