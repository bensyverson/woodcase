//
//  PasteSite+WhereCopied.swift
//  Woodcase
//

import Foundation

extension PasteSite {
    /// Each root back where it came from, on its own (``PasteTarget/whereCopied(documentID:)``).
    ///
    /// - Parameters:
    ///   - roots: The copied roots, carrying the canvas coordinates they were copied at.
    ///   - copies: What the clip knows of them, in the same order.
    ///   - home: Whether the target is the document the clip was copied out of.
    ///   - document: The target document.
    /// - Returns: The roots, placed, in the same order.
    static func whereCopied(
        _ roots: [PenNode],
        copies: Copies,
        home: Bool,
        in document: EditableDocument
    ) -> [Placed] {
        var layout: Layout?
        func laidOut() -> Layout {
            if let layout { return layout }
            let made = Layout(of: document)
            layout = made
            return made
        }
        let placed = zip(roots, zip(copies.rects, copies.origins)).map { root, known -> (Placed, keepsPlace: Bool) in
            let (rect, record) = known
            if let record, record.parentID == nil {
                return (Placed(node: root, parentID: nil, index: nil), home)
            }
            if home, let parentID = record?.parentID, let parent = document.nodes[parentID], isContainer(parent) {
                return (into(parentID, root, offset: record?.offset, layout: laidOut, in: document), true)
            }
            let canvas = origin(of: root)
            let center = rect.map { PenPoint(x: $0.x + $0.width / 2, y: $0.y + $0.height / 2) } ?? canvas
            guard let board = document.board(at: center) else {
                return (Placed(node: root, parentID: nil, index: nil), false)
            }
            return (into(board, root, offset: nil, layout: laidOut, in: document), false)
        }
        return ordered(placed, origins: copies.origins, in: document)
    }

    /// The roots with the index each lands at: one going back into its own parent right
    /// after its source node while that is still there, else at the index it had, clamped
    /// to the children there by then; any other appended.
    ///
    /// Each index counts the copies inserted before it, as the inserts apply in order, so
    /// copies from one parent keep their order among themselves.
    ///
    /// - Parameters:
    ///   - placed: The roots, placed, each with whether it keeps its place: back in the
    ///     parent it came from, in the document it came from.
    ///   - origins: Each root's origin, in the same order.
    ///   - document: The target document.
    /// - Returns: The roots, with their indices.
    private static func ordered(
        _ placed: [(Placed, keepsPlace: Bool)],
        origins: [PenClip.Origin?],
        in document: EditableDocument
    ) -> [Placed] {
        var siblings: [String?: [String]] = [:]
        return zip(placed, origins).map { pair, origin in
            var root = pair.0
            let parent = root.parentID
            var children = siblings[parent] ?? parent.map { document.children[$0] ?? [] } ?? document.rootOrder
            let at: Int
            if pair.keepsPlace, let origin {
                let source = origin.nodeID.flatMap { children.firstIndex(of: $0) }
                at = source.map { $0 + 1 } ?? min(max(origin.index ?? children.count, 0), children.count)
                root.index = at
            } else {
                at = children.count
            }
            children.insert(root.node.id, at: at)
            siblings[parent] = children
            return root
        }
    }

    /// One root into a container, after its last child: in the flow of a stack, else at
    /// `offset`, or at its canvas position in the container's coordinates when there is
    /// none.
    private static func into(
        _ containerID: String,
        _ root: PenNode,
        offset: PenPoint?,
        layout: () -> Layout,
        in document: EditableDocument
    ) -> Placed {
        if let container = document.nodes[containerID], isStack(container) {
            var flowing = root
            flowing.common.x = nil
            flowing.common.y = nil
            return Placed(node: flowing, parentID: containerID, index: nil)
        }
        let point = offset ?? layout().local(origin(of: root), in: containerID, of: document) ?? origin(of: root)
        return Placed(node: moved(root, to: point), parentID: containerID, index: nil)
    }
}
