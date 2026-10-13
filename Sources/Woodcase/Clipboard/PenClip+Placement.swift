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
    /// - Parameters:
    ///   - copies: The copied subtrees, one per selected node.
    ///   - selected: The selection, in the same order.
    ///   - document: The source document.
    /// - Returns: The subtrees, placed.
    static func placed(_ copies: [PenNode], of selected: [Selected], in document: EditableDocument) -> [PenNode] {
        guard selected.contains(where: { !$0.isRoot }) else { return copies }
        let expanded = PenVariableResolver.resolve(document.expanded(for: .canvas))
        let rects = PenLayoutEngine.layout(expanded)
        return zip(copies, selected).map { copy, node in
            guard !node.isRoot,
                  let placement = PenLayoutEngine.canvasPlacement(of: node.expandedID, in: expanded, layoutRects: rects)
            else { return copy }
            return moved(copy, to: placement)
        }
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
