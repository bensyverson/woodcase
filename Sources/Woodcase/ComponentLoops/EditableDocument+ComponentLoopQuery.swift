//
//  EditableDocument+ComponentLoopQuery.swift
//  Woodcase
//

import Foundation

/// Asking, before any edit, whether a drop, paste or swap would close a component loop.
///
/// An editor refuses such a drop at the drag — the container never highlights, the
/// cursor shows not-allowed — and runs the same check before a paste, an insert or a
/// swap commits. Each query describes the edit it stands for and asks the loop guard
/// (``EditingError/wouldCloseComponentLoop(path:)``) the question the guard would ask
/// when the edit is applied, so the answer is the guard's, never a second opinion.
///
/// **Cost.** Nothing is copied: the guard reads the graph through an overlay of the one
/// edit. A query that places no instance and no component — moving a subtree that holds
/// neither, say — returns after a walk of the moved subtree. Otherwise it walks from the
/// target up to the components that hold it and searches the component graph from the
/// newly rendered components; the graph's existing loops are memoized with the
/// expansion cache, so after an edit the first query (or the first expansion) rebuilds
/// them once, and every query until the next edit reads them free. Hovering over one
/// target, an editor may cache the answer per (dragged thing, target) until the
/// document's revision changes.
public extension EditableDocument {
    /// The loop that placing an instance of a component under a node would close.
    ///
    /// - Parameters:
    ///   - componentID: The component the new instance names.
    ///   - parentID: Where it would go, or `nil` for the canvas.
    /// - Returns: The loop, starting from the component the instance would land in —
    ///   each member renders the next, the last renders the first — or `nil` when the
    ///   placement closes none (including an unknown component or parent).
    func componentLoop(placingInstanceOf componentID: String, under parentID: String?) -> ComponentLoop? {
        let probe = PenNode(id: Self.loopProbeID, common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: componentID)))
        return componentLoop(closedBy: .insertNode(EditOperation.InsertNode(node: probe, parentID: parentID)))
    }

    /// The loop that pointing an instance at another component would close.
    ///
    /// - Parameters:
    ///   - refNodeID: The instance (`ref` node) being swapped.
    ///   - componentID: The component it would name instead.
    /// - Returns: The loop, as ``componentLoop(placingInstanceOf:under:)`` gives it, or
    ///   `nil` when the swap closes none or `refNodeID` is not an instance.
    func componentLoop(swapping refNodeID: String, to componentID: String) -> ComponentLoop? {
        guard case var .ref(data)? = nodes[refNodeID]?.kind else { return nil }
        data.ref = componentID
        return componentLoop(closedBy: .updateKind(EditOperation.UpdateKind(nodeID: refNodeID, kind: .ref(data))))
    }

    /// The loop that moving a node, with its subtree, under another would close — a
    /// Layers drag or a canvas reparent of something that holds instances.
    ///
    /// A parent that is an instance's slot — its expanded id, or a container in its
    /// content — is asked as the move would write it: one `children` override of the
    /// slot holding the node.
    ///
    /// - Parameters:
    ///   - nodeID: The node to move, stored.
    ///   - parentID: Its new parent — a stored id, or a slot's expanded id — or `nil`
    ///     for the canvas.
    /// - Returns: The loop, as ``componentLoop(placingInstanceOf:under:)`` gives it, or
    ///   `nil` when the move closes none.
    func componentLoop(moving nodeID: String, under parentID: String?) -> ComponentLoop? {
        guard nodes[nodeID] != nil else { return nil }
        if let parentID, nodes[parentID] == nil, let subtree = try? materializeSubtree(rootID: nodeID) {
            return componentLoop(inserting: subtree, under: parentID)
        }
        return componentLoop(closedBy: .moveNode(EditOperation.MoveNode(nodeID: nodeID, newParentID: parentID)))
    }

    /// The loop that inserting a subtree under a node would close — a paste or a
    /// duplicate, which may hold instances and components.
    ///
    /// - Parameters:
    ///   - subtree: The node to insert, with its children.
    ///   - parentID: Where it would go — a stored id, or a slot's expanded id — or `nil`
    ///     for the canvas.
    /// - Returns: The loop, as ``componentLoop(placingInstanceOf:under:)`` gives it, or
    ///   `nil` when the insert closes none.
    func componentLoop(inserting subtree: PenNode, under parentID: String?) -> ComponentLoop? {
        if let parentID, nodes[parentID] == nil {
            return slotFillOperations(inserting: subtree, under: parentID).lazy.compactMap(componentLoop(closedBy:)).first
        }
        return componentLoop(closedBy: .insertNode(EditOperation.InsertNode(node: subtree, parentID: parentID)))
    }
}

extension EditableDocument {
    /// The id of the instance a placement query probes with: one no stored node can have,
    /// since it is never an id the document hands out.
    static let loopProbeID = "\u{0}component-loop-probe"

    /// The overrides that would put a subtree into a slot, or none when the parent is
    /// not a slot or a container in one.
    ///
    /// - Parameters:
    ///   - subtree: The node, with its children.
    ///   - parentID: The slot's expanded id, or a container's in its content.
    func slotFillOperations(inserting subtree: PenNode, under parentID: String) -> [EditOperation] {
        let session = SlotEditSession(document: self)
        guard case let .slot(refID, slotKey, containerKey)? = try? SlotDestination(parentID, in: session),
              let json = try? SlotJSON.json(of: subtree),
              session.insert(json, refID: refID, slotKey: slotKey, containerKey: containerKey, at: nil)
        else { return [] }
        return session.overrideOperations()
    }

    /// The loop an operation would close, asked of the write guard without applying it.
    ///
    /// - Parameter operation: The edit, otherwise valid against the document.
    /// - Returns: The loop, starting from the component written into, or `nil`.
    func componentLoop(closedBy operation: EditOperation) -> ComponentLoop? {
        guard let edit = componentGraphEdit(for: operation), let path = loopClosed(by: edit) else { return nil }
        let cycle = path.count > 1 && path.first == path.last ? path.dropLast() : path[...]
        return ComponentLoop(members: cycle.map { id in
            ComponentLoop.Member(id: id, name: componentNode(id)?.common.name ?? id)
        })
    }
}
