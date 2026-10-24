//
//  EditPlanner+SlotMove.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans moving nodes to another parent — into, within or out of an instance's slot as
    /// well as anywhere outside instances.
    ///
    /// A slot is the one place inside an instance that takes children (Penumbra spec §13.5
    /// rules 4–7): its content is the instance's own, so it rearranges like any frame,
    /// and the result is written as **one `children` override of the slot** — the
    /// instance's fill. A node moved in from the document leaves its old parent (a
    /// delete, its attached connectors going with it); one moved out of a slot becomes an
    /// ordinary node there. The first structural change on a slot that still shows its
    /// component's default content copies that content into a fill — its overrides folded
    /// in, fresh ids — then applies the change, in the same plan (rule 6);
    /// ``StructuralEditPlan/renamed(_:)`` carries a selection across.
    ///
    /// The nodes land together, in the order given: the first at `index`, each next one
    /// after it, as successive moves at `index`, `index + 1`, … would place them — the
    /// index a drop's insertion cursor names. Each keeps its drawn size and, given
    /// `offset`, its drawn place, exactly as ``planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)``
    /// plans a single move; a move with no node in a slot plans exactly what that does,
    /// node by node.
    ///
    /// ```swift
    /// // Dragging the third row of a list slot to the top.
    /// let plan = try EditPlanner.planMove(
    ///     nodeIDs: ["Filled/Row3/ItemA"], into: "Filled/List", at: 0, in: document, layout: layout
    /// )
    /// ```
    ///
    /// Refused for a node inside an instance outside its slots' content, and for a target
    /// inside an instance that is neither a slot nor a container in one
    /// (``EditRefusal/Code/insideInstance``); for an id naming nothing
    /// (``EditRefusal/Code/addressNotFound``); for a node moved into itself — an instance
    /// into one of its own slots included (``EditRefusal/Code/wouldCreateCycle``); and for
    /// a move that would make a component contain itself
    /// (``EditRefusal/Code/wouldCloseComponentLoop``).
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes, by stored id or the expanded id an editor holds.
    ///   - parentID: The new parent — a stored id, a slot frame's or a slot content
    ///     container's expanded id — or `nil` for the canvas.
    ///   - index: Where the first node goes among the new parent's children; `nil` puts
    ///     them last, on top.
    ///   - offset: How far the nodes are carried on the canvas, to keep their drawn
    ///     place; `nil` plans only the move and the sizes they keep.
    ///   - snapping: How each new `x`/`y` is rounded.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands.
    /// - Returns: The edits, to submit as one, and where the nodes answer afterward.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planMove(
        nodeIDs: [String],
        into parentID: String?,
        at index: Int? = nil,
        keepingDrawnPlace offset: PenPoint? = nil,
        snapping: PlacementSnapping = .none,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> StructuralEditPlan {
        let session = SlotEditSession(document: document)
        let destination = try SlotDestination(parentID, in: session)
        let origins = try SlotOrigin.topMost(nodeIDs.map { id throws(EditRefusal) in try SlotOrigin(id, in: session) }, in: session)
        try destination.refuseCycles(moving: origins, in: session)

        guard case let .document(parent) = destination, origins.allSatisfy(\.isStored) else {
            var move = SlotMove(session: session, destination: destination, layout: layout)
            return try move.plan(origins, at: index, keepingDrawnPlace: offset, snapping: snapping)
        }
        var operations: [EditOperation] = []
        for (offsetInRun, origin) in origins.enumerated() {
            guard case let .document(id) = origin else { continue }
            operations += try planStoredMove(
                nodeID: id, into: parent, at: index.map { $0 + offsetInRun },
                keepingDrawnPlace: offset, snapping: snapping, in: document, layout: layout
            )
        }
        let placed = origins.compactMap { origin -> String? in
            guard case let .document(id) = origin else { return nil }
            return document.expandedID(of: .node(id: id))
        }
        return StructuralEditPlan(operations: operations, placedIDs: placed)
    }
}
