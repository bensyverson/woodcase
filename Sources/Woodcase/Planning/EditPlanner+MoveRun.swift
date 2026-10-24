//
//  EditPlanner+MoveRun.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// Plans moving a run of stored nodes to a stored parent, as one edit: the nodes land
    /// side by side in the order given, at `index` counted among the parent's children
    /// with the moving nodes taken out (``RunLanding``), each keeping its drawn size and,
    /// given `offset`, its drawn place, as a single move does.
    ///
    /// Each move is checked against the document as it stands without its index, which
    /// is right only once the moves before it have landed; the run's index is checked
    /// against the children left once the run is out.
    ///
    /// - Parameters:
    ///   - ids: The nodes, stored, top-most only.
    ///   - parentID: The new parent's stored id, or `nil` for the canvas.
    ///   - index: Where the first node goes, counted without the moving nodes; `nil`
    ///     puts the run last.
    ///   - offset: How far the nodes are carried on the canvas, or `nil`.
    ///   - snapping: How each new `x`/`y` is rounded.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands.
    /// - Returns: Each node's move, then any size and place it keeps.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planStoredRun(
        _ ids: [String],
        into parentID: String?,
        at index: Int?,
        keepingDrawnPlace offset: PenPoint?,
        snapping: PlacementSnapping,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> [EditOperation] {
        var landing = try runLanding(at: index, in: parentID, moving: ids, address: ids.first ?? "", of: document)
        var operations: [EditOperation] = []
        for id in ids {
            operations += try planRunStep(
                id, into: parentID, at: landing.land(id), keepingDrawnPlace: offset, snapping: snapping,
                in: document, layout: layout
            )
        }
        return operations
    }

    /// Plans one stored node's move in a run, at the index its ``RunLanding`` gave it:
    /// checked against the document as it stands without that index, which is right only
    /// once the run's edits before it have landed.
    ///
    /// - Parameters:
    ///   - id: The node, stored.
    ///   - parentID: The new parent's stored id, or `nil` for the canvas.
    ///   - index: The index its landing gave it, or `nil` to put it last.
    ///   - offset: How far the node is carried on the canvas, or `nil`.
    ///   - snapping: How its new `x`/`y` are rounded.
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands.
    /// - Returns: The move, then any size and place it keeps.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planRunStep(
        _ id: String,
        into parentID: String?,
        at index: Int?,
        keepingDrawnPlace offset: PenPoint?,
        snapping: PlacementSnapping,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> [EditOperation] {
        try validateMove(id, into: parentID, at: nil, address: id, in: document)
        return storedMoveOperations(
            id, into: parentID, at: index, keepingDrawnPlace: offset, snapping: snapping, in: document, layout: layout
        )
    }

    /// The landing of a run in a stored parent, or the refusal of an index past the
    /// children left once the run is out.
    ///
    /// - Parameters:
    ///   - index: Where the run's first node goes, counted without the moving nodes.
    ///   - parentID: The new parent's stored id, or `nil` for the canvas.
    ///   - ids: The stored nodes moving; any not among the parent's children are ignored.
    ///   - address: What a refusal names.
    ///   - document: The document, as it stands.
    static func runLanding(
        at index: Int?, in parentID: String?, moving ids: [String], address: String, of document: EditableDocument
    ) throws(EditRefusal) -> RunLanding {
        let children = parentID.map(document.childIDs(of:)) ?? document.rootOrder
        do {
            return try RunLanding(index: index, among: children, moving: Set(ids))
        } catch {
            throw EditRefusal(error, address: address, in: document)
        }
    }
}
