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
    /// The nodes land together, side by side in the order given, the first at `index`.
    /// **`index` counts the new parent's children with the moving nodes taken out**, as a
    /// stack reorder does — wherever the nodes come from, slot content or stored, one
    /// parent or several — so a run moved forward past its own siblings lands together:
    /// in `[A, B, C, D, E]`, moving `[A, B]` to index 2 (after `D` in `[C, D, E]`) gives
    /// `[C, D, A, B, E]`. For a single node this is the index a `MoveNode` takes. An index
    /// past the children left once the run is out is refused. In a stored parent the run
    /// is written as one `MoveNode` per node, each at the index that keeps the run whole
    /// once the moves before it have landed (leaf 14SEVW); submit the operations as one
    /// edit, one undo step. Each node keeps its drawn size and, given `offset`, its drawn
    /// place, exactly as ``planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)``
    /// plans a single move.
    ///
    /// ```swift
    /// // Dragging the third row of a list slot to the top.
    /// let plan = try EditPlanner.planMove(
    ///     nodeIDs: ["Filled/Row3/ItemA"], into: "Filled/List", at: 0, in: document, layout: layout
    /// )
    /// // Moving the first two children of a stack after its fourth: [C, D, A, B, E].
    /// let reorder = try EditPlanner.planMove(nodeIDs: ["A", "B"], into: "Stack", at: 2, in: document, layout: layout)
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
    ///   - index: Where the first node goes among the new parent's children, counted
    ///     without the moving nodes; `nil` puts them last, on top.
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
        let ids = origins.compactMap { origin -> String? in
            guard case let .document(id) = origin else { return nil }
            return id
        }
        let operations = try planStoredRun(
            ids, into: parent, at: index, keepingDrawnPlace: offset, snapping: snapping, in: document, layout: layout
        )
        return StructuralEditPlan(operations: operations, placedIDs: ids)
    }
}
