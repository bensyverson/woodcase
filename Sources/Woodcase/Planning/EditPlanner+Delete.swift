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
    /// Refused for an id inside a component instance (``EditRefusal/Code/insideInstance``)
    /// and for one naming nothing (``EditRefusal/Code/addressNotFound``).
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes to delete: stored ids, or the expanded ids an editor holds.
    ///   - document: The document, as it stands.
    /// - Returns: The deletes, connectors first, with what they remove.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planDelete(nodeIDs: [String], in document: EditableDocument) throws(EditRefusal) -> DeletionPlan {
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

extension EditPlanner {
    /// The connectors with an end attached to one of `removed`, none of them among it, in
    /// document order.
    ///
    /// An end's path names a node by id, or steps into instances by id
    /// (`instance/child`); it is attached to a removed node when any of those ids is one.
    /// Connectors are found at any depth, though Pen keeps them only at the top level.
    ///
    /// - Parameters:
    ///   - removed: Every node an edit removes, descendants included.
    ///   - document: The document, before the edit.
    /// - Returns: The connectors to delete with them.
    static func connectorIDs(attachedTo removed: Set<String>, in document: EditableDocument) -> [String] {
        guard !removed.isEmpty else { return [] }
        let attached: Set<String> = Set(document.nodes.compactMap { id, node in
            guard !removed.contains(id), case let .connection(data) = node.kind else { return nil }
            let ends = [data.source.path, data.target.path]
            let touches = ends.contains { path in
                path.split(separator: "/").contains { removed.contains(String($0)) }
            }
            return touches ? id : nil
        })
        guard !attached.isEmpty else { return [] }
        return document.nodeIDsInDocumentOrder().filter(attached.contains)
    }
}
