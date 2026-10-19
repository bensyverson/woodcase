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
    /// Only the size is planned: a caller that drops the node at a point writes its
    /// `x`/`y` itself, after these edits.
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
    ///   - document: The document, as it stands.
    ///   - layout: The layout of `document` as it stands, which the drawn size is read from.
    /// - Returns: The edits, to submit as one: the move, then any size it keeps.
    /// - Throws: ``EditRefusal`` naming why nothing should be written.
    static func planMove(
        nodeID: String,
        into parentID: String?,
        at index: Int? = nil,
        in document: EditableDocument,
        layout: PenLayoutState
    ) throws(EditRefusal) -> [EditOperation] {
        let id = try restructuredID(nodeID, in: document)
        let move = EditOperation.moveNode(EditOperation.MoveNode(nodeID: id, newParentID: parentID, index: index))
        do {
            try document.validate(move)
        } catch {
            throw EditRefusal(error, address: nodeID, in: document)
        }
        return [move] + keptSizes(movingNode: id, into: parentID, in: document) { layout }
    }
}

extension EditPlanner {
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
        guard !laidOut, let node = document.node(id: id),
              let size = layout.rects[document.expandedID(of: .node(id: id))]?.drawnSize
        else { return [:] }
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
