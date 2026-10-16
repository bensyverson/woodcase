//
//  PenClip+Placement.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// The copied subtrees, each one that was not a root moved to where it was drawn.
    ///
    /// A clip's roots are measured on the canvas, so a node copied out of a parent gets
    /// the canvas position of its own origin — the point its `x` and `y` name, which for
    /// a turned or flipped node is its anchor, not its bounds. It keeps its own turn; a
    /// turn it inherited from an ancestor is not carried. A width or height that filled
    /// its container becomes the size it was drawn at, since a root has no container to
    /// fill — its origin keeps the original, which a paste into a stack writes back — and
    /// `layoutPosition`, which only a parent's layout reads, is dropped.
    ///
    /// The document is laid out only when some copied node was not a root.
    ///
    /// Each one also reports where it came from (``PenClip/Origin``): its parent and its
    /// offset there — the point its `x` and `y` named, as drawn — and its board and its
    /// offset from that board's corner, in the board's coordinates. A root reports only
    /// its canvas position, as its offset from the canvas origin.
    ///
    /// - Parameters:
    ///   - copies: The copied subtrees, one per selected node.
    ///   - selected: The selection, in the same order.
    ///   - document: The source document.
    /// - Returns: The subtrees, placed, and each one's origin, in the same order.
    static func placed(
        _ copies: [PenNode],
        of selected: [Selected],
        in document: EditableDocument
    ) -> (nodes: [PenNode], origins: [Origin]) {
        let atTop = zip(copies, selected).map { copy, node in
            Origin(
                parentID: nil, offset: nil, boardID: nil, boardOffset: PasteSite.origin(of: copy),
                nodeID: node.key, index: index(of: node, in: document)
            )
        }
        guard selected.contains(where: { !$0.isRoot }) else { return (copies, atTop) }
        let expanded = PenVariableResolver.resolve(document.expanded(for: .canvas))
        let rects = PenLayoutEngine.layout(expanded)
        let drawn = drawnNodes(selected.filter { !$0.isRoot }.map(\.expandedID), in: expanded)
        var nodes: [PenNode] = []
        var origins: [Origin] = []
        for (index, (copy, node)) in zip(copies, selected).enumerated() {
            guard !node.isRoot,
                  let placement = PenLayoutEngine.canvasPlacement(of: node.expandedID, in: expanded, layoutRects: rects)
            else {
                nodes.append(copy)
                origins.append(node.isRoot ? atTop[index] : Origin(
                    parentID: node.parentID, offset: nil, boardID: node.boardID, boardOffset: atTop[index].boardOffset,
                    nodeID: node.key, index: atTop[index].index
                ))
                continue
            }
            let canvas = placement.transform.apply(to: PenPoint(x: 0, y: 0))
            let board = node.boardID.flatMap { boardID in
                PenLayoutEngine.canvasPlacement(
                    of: document.expandedID(of: .node(id: boardID)), in: expanded, layoutRects: rects
                )?.transform.inverted()?.apply(to: canvas)
            }
            let root = moved(copy, to: placement)
            nodes.append(root.node)
            origins.append(Origin(
                parentID: node.parentID,
                offset: drawn[node.expandedID].flatMap { found in
                    rects[found.id].map { rect in
                        PenLayoutEngine.placement(of: found, rect: rect, layoutRects: rects)
                            .transform.apply(to: PenPoint(x: 0, y: 0))
                    }
                },
                boardID: node.boardID,
                boardOffset: board ?? canvas,
                nodeID: node.key,
                index: atTop[index].index,
                width: root.filled[.width],
                height: root.filled[.height]
            ))
        }
        return (nodes, origins)
    }

    /// Some nodes of an expanded document, found by id.
    ///
    /// - Parameters:
    ///   - ids: The expanded ids to find.
    ///   - expanded: The expanded document.
    /// - Returns: Each one found, by id.
    private static func drawnNodes(_ ids: [String], in expanded: PenDocument) -> [String: PenNode] {
        let wanted = Set(ids)
        var found: [String: PenNode] = [:]
        var pending = expanded.children
        while let node = pending.popLast(), found.count < wanted.count {
            if wanted.contains(node.id) {
                found[node.id] = node
            }
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return found
    }

    /// One subtree, moved to its canvas placement.
    ///
    /// - Parameters:
    ///   - node: The copied subtree.
    ///   - placement: Where it was drawn on the canvas.
    /// - Returns: The subtree as a root at that place, and the sizing of each dimension
    ///   that filled its container there, which it now writes at its drawn size.
    private static func moved(
        _ node: PenNode,
        to placement: PenPlacement
    ) -> (node: PenNode, filled: [Dimension: PenSizing]) {
        var result = node
        let origin = placement.transform.apply(to: PenPoint(x: 0, y: 0))
        result.common.x = .literal(origin.x)
        result.common.y = .literal(origin.y)
        result.common.layoutPosition = nil
        var filled: [Dimension: PenSizing] = [:]
        for dimension in Dimension.allCases {
            guard let sizing = sizing(on: dimension, of: result), case .fillContainer = sizing else { continue }
            filled[dimension] = sizing
            result = setting(.fixed(dimension.of(PenSize(width: placement.box.width, height: placement.box.height))),
                             on: dimension, of: result)
        }
        return (result, filled)
    }

    /// Where a stored node sits among its parent's children — among the roots for a root
    /// — or `nil` for a node drawn inside an instance.
    private static func index(of node: Selected, in document: EditableDocument) -> Int? {
        guard node.instanceID == nil else { return nil }
        guard let parentID = document.parents[node.key] else { return document.rootOrder.firstIndex(of: node.key) }
        return document.children[parentID]?.firstIndex(of: node.key)
    }
}
