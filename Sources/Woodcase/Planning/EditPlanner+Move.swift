//
//  EditPlanner+Move.swift
//  Woodcase
//

import Foundation

public extension EditPlanner {
    /// Plans moving a node to another parent, keeping the size it is drawn at where its new
    /// parent does not lay it out.
    ///
    /// Ben's ruling of 2026-10-15 (Penumbra spec §4.4, leaf skbh2k): a `fill_container`
    /// width or height takes its room from a stack, which offers it on both axes — its
    /// share of the main axis, and the cross axis stretched. A free frame (`layout: none`),
    /// a group and the canvas offer none, and neither does a stack to a child it does not
    /// place (`layoutPosition: absolute`), so there a fill would settle at its fallback or
    /// its content — often zero. So when the node's new parent does not lay it out, each
    /// `fill_container` dimension is written as the number it was drawn at; a
    /// `fit_content` one stays, since it works anywhere, and a move into a stack writes
    /// nothing but the move. Figma does the same when a layer leaves an auto-layout frame.
    ///
    /// Given `offset`, a node its new parent places by position — a free frame, a group,
    /// the canvas, or a stack holding it `absolute` — also keeps its **drawn place**,
    /// carried by `offset` on the canvas: its `x`/`y`, rotation and flips are rewritten
    /// together, so its quad on the canvas is the one it was drawn as, moved. A parent
    /// turned or flipped differently from the old one changes the node's own turn and
    /// flips — a flipped parent reverses the sense of its child's turn, so the turn is not
    /// the old one plus the difference of the parents' — and a rotation bound to a
    /// variable is written as the number it must be. A node a stack takes into its flow
    /// is placed by the stack, so there the offset changes nothing. Without `offset` only
    /// the size is planned, and a caller that drops the node at a point writes its `x`/`y`
    /// itself, after these edits.
    ///
    /// ```swift
    /// // A free reparent drop: the node lands where the pointer carried it, turned as it was drawn.
    /// let operations = try EditPlanner.planMove(
    ///     nodeID: "Chip", into: "Board", keepingDrawnPlace: PenPoint(x: 120, y: -40), in: document, layout: layout
    /// )
    /// ```
    ///
    /// Slot content and slots are refused here as inside an instance: a caller that
    /// plans a drag node by node and concatenates the plans would write each slot against
    /// the slot as it stood. Slots are reached through
    /// ``planMove(nodeIDs:into:at:keepingDrawnPlace:snapping:in:layout:)``, which writes
    /// each slot once.
    ///
    /// Refused inside a component instance (``EditRefusal/Code/insideInstance``), for an
    /// id naming nothing (``EditRefusal/Code/addressNotFound``), for a parent that is the
    /// node or inside it (``EditRefusal/Code/wouldCreateCycle``), and for a move that would
    /// make a component contain itself (``EditRefusal/Code/wouldCloseComponentLoop``, whose
    /// ``EditRefusal/detail`` is the loop).
    ///
    /// - Parameters:
    ///   - nodeID: The node: a stored id, or the expanded id an editor holds (an
    ///     instance's root resolves to its `ref`).
    ///   - parentID: The new parent's stored id, or `nil` for the canvas.
    ///   - index: Where among the new parent's children it goes; `nil` puts it last, on top.
    ///   - offset: How far the node is carried on the canvas, to keep its drawn place
    ///     there; `nil` plans only the move and the size it keeps.
    ///   - snapping: How the node's new `x`/`y` are rounded before they are compared with
    ///     the stored ones; ``PlacementSnapping/wholePoints`` lands a drop on whole points in
    ///     the new parent's space, and writes a stored fractional coordinate rounded even
    ///     when the move leaves it in place. Rotation and flips are not snapped, and it
    ///     changes nothing without `offset`.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands, which the drawn size and place
    ///     are read from.
    /// - Returns: The edits, to submit as one: the move, then any size and place it keeps.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planMove(
        nodeID: String,
        into parentID: String?,
        at index: Int? = nil,
        keepingDrawnPlace offset: PenPoint? = nil,
        snapping: PlacementSnapping = .none,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> [EditOperation] {
        try planStoredMove(
            nodeID: nodeID, into: parentID, at: index, keepingDrawnPlace: offset, snapping: snapping,
            in: document, layout: layout
        )
    }
}

extension EditPlanner {
    /// Plans moving a stored node to a stored parent: the single move
    /// ``planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)`` plans. A run of
    /// several is ``planStoredRun(_:into:at:keepingDrawnPlace:snapping:in:layout:)``.
    ///
    /// - Parameters: As ``planMove(nodeID:into:at:keepingDrawnPlace:snapping:in:layout:)``.
    /// - Returns: The move, then any size and place it keeps.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planStoredMove(
        nodeID: String,
        into parentID: String?,
        at index: Int?,
        keepingDrawnPlace offset: PenPoint?,
        snapping: PlacementSnapping,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> [EditOperation] {
        let id = try restructuredID(nodeID, in: document)
        try validateMove(id, into: parentID, at: index, address: nodeID, in: document)
        return storedMoveOperations(
            id, into: parentID, at: index, keepingDrawnPlace: offset, snapping: snapping, in: document, layout: layout
        )
    }

    /// Runs the document's own checks on one stored move.
    ///
    /// - Parameters:
    ///   - id: The node, stored.
    ///   - parentID: The new parent's stored id, or `nil` for the canvas.
    ///   - index: The index to check, or `nil` to check the move alone.
    ///   - address: What a refusal names.
    ///   - document: The document, as it stands.
    /// - Throws: ``EditRefusal`` naming why the document refuses the move.
    static func validateMove(
        _ id: String, into parentID: String?, at index: Int?, address: String, in document: EditableDocument
    ) throws(EditRefusal) {
        do {
            try document.validate(.moveNode(EditOperation.MoveNode(nodeID: id, newParentID: parentID, index: index)))
        } catch {
            throw EditRefusal(error, address: address, in: document)
        }
    }

    /// A checked stored move's edits: the move, then any size and place it keeps.
    ///
    /// - Parameters: As ``planRunStep(_:into:at:keepingDrawnPlace:snapping:in:layout:)``.
    /// - Returns: The move, then any size and place it keeps.
    static func storedMoveOperations(
        _ id: String,
        into parentID: String?,
        at index: Int?,
        keepingDrawnPlace offset: PenPoint?,
        snapping: PlacementSnapping,
        in document: EditableDocument,
        layout: PenLayoutState
    ) -> [EditOperation] {
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: id, newParentID: parentID, index: index))
        guard let offset, let placing = placingByPosition(id, in: parentID, of: document) else {
            return [move] + keptSizes(movingNode: id, into: parentID, in: document) { layout }
        }
        let writes = placementWrites(
            of: id, from: document.parentID(of: id),
            newParentMap: canvasMap(of: parentID, in: document, layout: layout) ?? .identity,
            newParentFlips: flipParity(of: parentID, in: document),
            placing: placing, movedBy: offset, snapping: snapping, in: document, layout: layout
        )
        return writes.isEmpty ? [move] : [move, .setProperties(EditOperation.SetProperties(nodeID: id, properties: writes))]
    }
}

extension EditPlanner {
    /// How a parent places a node by its own `x`/`y`, or `nil` when it takes the node into
    /// its flow.
    ///
    /// - Parameters:
    ///   - id: The node, stored.
    ///   - parentID: Its new parent, or `nil` for the canvas.
    ///   - document: The document, as it stands.
    static func placingByPosition(_ id: String, in parentID: String?, of document: EditableDocument) -> Placing? {
        guard laysOut(parentID, in: document) else { return .free }
        return document.node(id: id)?.common.layoutPosition == .absolute ? .absolute : nil
    }

    /// The edit that keeps a moved node's fill sizes at the size it was drawn at, when its
    /// new parent does not lay it out; empty otherwise.
    ///
    /// - Parameters:
    ///   - id: The node, stored.
    ///   - parentID: Its new parent, or `nil` for the canvas.
    ///   - document: The document, as it stands before the move.
    ///   - layout: The layout of the document as it stands, asked for only when the node
    ///     has a fill size to keep, so a move that keeps none lays nothing out.
    /// - Returns: Zero or one `setProperties`.
    static func keptSizes(
        movingNode id: String,
        into parentID: String?,
        in document: EditableDocument,
        layout: () -> PenLayoutState
    ) -> [EditOperation] {
        guard let node = document.node(id: id), !fillPaths(of: node).isEmpty else { return [] }
        let laidOut = laysOut(parentID, in: document) && node.common.layoutPosition != .absolute
        let writes = keptSizeWrites(of: id, laidOut: laidOut, in: document, layout: layout())
        return writes.isEmpty ? [] : [.setProperties(EditOperation.SetProperties(nodeID: id, properties: writes))]
    }

    /// The writes that keep a node's fill sizes at the size it was drawn at, unless its
    /// new parent lays it out.
    ///
    /// - Parameters:
    ///   - id: The node, stored.
    ///   - laidOut: Whether its new parent lays it out: a stack, holding it in flow.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of the document as it stands.
    /// - Returns: Each `fill_container` dimension's path and drawn size; empty when the
    ///   new parent lays it out, or the layout drew no such node.
    static func keptSizeWrites(
        of id: String,
        laidOut: Bool,
        in document: EditableDocument,
        layout: PenLayoutState
    ) -> [String: AnyCodable] {
        guard let node = document.node(id: id) else { return [:] }
        return keptSizeWrites(
            of: node, drawnSize: layout.rects[document.expandedID(of: .node(id: id))]?.drawnSize, laidOut: laidOut
        )
    }

    /// The writes that keep a node's fill sizes at a drawn size, unless its new parent
    /// lays it out — for a node with no storage of its own as well as a stored one.
    ///
    /// - Parameters:
    ///   - node: The node, as drawn.
    ///   - drawnSize: The size the layout drew it at, or `nil` when it drew none.
    ///   - laidOut: Whether its new parent lays it out: a stack, holding it in flow.
    /// - Returns: Each `fill_container` dimension's path and drawn size.
    static func keptSizeWrites(of node: PenNode, drawnSize: PenSize?, laidOut: Bool) -> [String: AnyCodable] {
        guard !laidOut, let size = drawnSize else { return [:] }
        var writes: [String: AnyCodable] = [:]
        for path in fillPaths(of: node) {
            writes[path] = number(path == widthPath ? size.width : size.height)
        }
        return writes
    }

    /// The paths of a node's dimensions that fill their container, with or without a
    /// fallback.
    private static func fillPaths(of node: PenNode) -> [String] {
        [widthPath, heightPath].filter { path in
            guard case let .string(sizing)? = try? NodePropertyCodec.value(at: path, of: node) else { return false }
            return sizing.hasPrefix(fillContainer)
        }
    }

    /// The property path of a node's width.
    static let widthPath = NodePropertyCodec.kindPrefix + "width"

    /// The property path of a node's height.
    static let heightPath = NodePropertyCodec.kindPrefix + "height"

    /// How a sizing that fills its container is written, with or without a fallback.
    private static let fillContainer = "fill_container"
}
