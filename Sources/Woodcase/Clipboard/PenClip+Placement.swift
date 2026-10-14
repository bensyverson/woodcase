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
    /// fill, and `layoutPosition`, which only a parent's layout reads, is dropped.
    ///
    /// The document is laid out only when some copied node was not a root.
    ///
    /// Each one that was not a root also reports its offset in its parent: the point its
    /// `x` and `y` named there, as drawn (``PenClip/offsets``).
    ///
    /// - Parameters:
    ///   - copies: The copied subtrees, one per selected node.
    ///   - selected: The selection, in the same order.
    ///   - document: The source document.
    /// - Returns: The subtrees, placed, and each one's offset in its parent — `nil` for a
    ///   root — in the same order.
    static func placed(
        _ copies: [PenNode],
        of selected: [Selected],
        in document: EditableDocument
    ) -> (nodes: [PenNode], offsets: [PenPoint?]) {
        guard selected.contains(where: { !$0.isRoot }) else {
            return (copies, Array(repeating: nil, count: copies.count))
        }
        let expanded = PenVariableResolver.resolve(document.expanded(for: .canvas))
        let rects = PenLayoutEngine.layout(expanded)
        let drawn = drawnNodes(selected.filter { !$0.isRoot }.map(\.expandedID), in: expanded)
        var nodes: [PenNode] = []
        var offsets: [PenPoint?] = []
        for (copy, node) in zip(copies, selected) {
            guard !node.isRoot,
                  let placement = PenLayoutEngine.canvasPlacement(of: node.expandedID, in: expanded, layoutRects: rects)
            else {
                nodes.append(copy)
                offsets.append(nil)
                continue
            }
            nodes.append(moved(copy, to: placement))
            offsets.append(drawn[node.expandedID].flatMap { found in
                rects[found.id].map { rect in
                    PenLayoutEngine.placement(of: found, rect: rect, layoutRects: rects)
                        .transform.apply(to: PenPoint(x: 0, y: 0))
                }
            })
        }
        return (nodes, offsets)
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
    /// - Returns: The subtree as a root at that place.
    private static func moved(_ node: PenNode, to placement: PenPlacement) -> PenNode {
        var result = node
        let origin = placement.transform.apply(to: PenPoint(x: 0, y: 0))
        result.common.x = .literal(origin.x)
        result.common.y = .literal(origin.y)
        result.common.layoutPosition = nil
        for (path, drawn) in [(widthPath, placement.box.width), (heightPath, placement.box.height)] {
            guard case let .string(sizing)? = try? NodePropertyCodec.value(at: path, of: result),
                  sizing.hasPrefix(fillContainer),
                  let fixed = try? NodePropertyCodec.setting(.double(drawn), at: path, on: result)
            else { continue }
            result = fixed
        }
        return result
    }

    /// The property path of a node's width.
    private static let widthPath = "kind.width"

    /// The property path of a node's height.
    private static let heightPath = "kind.height"

    /// How a sizing that fills its container is written, with or without a fallback.
    private static let fillContainer = "fill_container"
}
