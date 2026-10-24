//
//  EditPlanner+Delete.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans Delete: the nodes, and every connector attached to them or to anything inside
    /// them, as one edit.
    ///
    /// A connector whose end names a node the delete removes would be left pointing at
    /// nothing — Pen's format has no free end — so it goes too, in the same edit, and one
    /// undo brings the nodes and the connectors back together (Ben's ruling of 2026-10-23,
    /// Penumbra spec §11). An end is attached to a removed node when any id its path names
    /// is one: the node itself, a node inside it, an instance inside it (`Chip/Label`), or
    /// a component's own node that an instance shows (`Label` in `Chip/Label`).
    ///
    /// Each id is deleted once: an id given twice, or one inside another given id, is
    /// dropped, and a connector that is itself deleted is not taken again. Delete and Cut
    /// in an editor, `woodcase rm`, a batch's `rm` line and a script's remove all plan
    /// through this, so they agree on what a delete takes.
    ///
    /// The plan does not check that a component being deleted has no instances: applying
    /// it refuses that (``EditingError/componentHasInstances(componentID:instanceIDs:)``),
    /// and `woodcase rm --detach` detaches them first.
    ///
    /// Content in an instance's slot deletes from the slot's fill, one `children`
    /// override of the slot, the default content copied into a fill first when the slot
    /// shows it (Penumbra spec §13.5 rules 4 and 6); its ``DeletionPlan/nodeIDs`` are
    /// expanded ids.
    ///
    /// Refused for an id inside a component instance outside its slots' content
    /// (``EditRefusal/Code/insideInstance``) and for one naming nothing
    /// (``EditRefusal/Code/addressNotFound``).
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes to delete: stored ids, or the expanded ids an editor holds.
    ///   - document: The document, as it stands.
    /// - Returns: The deletes, connectors first, with what they remove.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planDelete(nodeIDs: [String], in document: EditableDocument) throws(EditRefusal) -> DeletionPlan {
        if let slotted = try planSlotDelete(nodeIDs: nodeIDs, in: document) { return slotted }
        var stored: [String] = []
        for id in nodeIDs {
            let node = try restructuredID(id, in: document)
            if !stored.contains(node) { stored.append(node) }
        }
        let asked = Set(stored)
        let topMost = stored.filter { id in
            !document.ancestors(of: id).contains(where: asked.contains)
        }
        let removed = Set(topMost.flatMap { document.descendantIDs(of: $0) })
        let connectors = connectorIDs(attachedTo: removed, in: document)
        let deletes = (connectors + topMost).map { id in
            EditOperation.deleteNode(EditOperation.DeleteNode(nodeID: id))
        }
        return DeletionPlan(operations: deletes, nodeIDs: topMost, connectorIDs: connectors)
    }
}
