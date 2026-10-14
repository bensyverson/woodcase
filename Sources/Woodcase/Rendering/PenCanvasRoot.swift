//
//  PenCanvasRoot.swift
//  Woodcase
//

import Foundation

/// One root of a selection drawn where the canvas draws it: the node, the map from its
/// parent's coordinates to the canvas, and every clipping ancestor it is seen through.
///
/// The seam both multi-root outputs share — ``PenRenderer/render(_:layoutRects:rootNodeIDs:bounds:scale:colorSpace:imageProvider:postIt:)``
/// and ``SVGExporter`` — so a PNG and an SVG of the same selection agree on where each
/// root lands and what cuts it. An ancestor contributes its placement and, when it is a
/// frame that clips, its outline; never its paint, opacity, blend mode or effects. A copy
/// of a node out of a translucent frame is the node, not the node as dimmed by its frame.
struct PenCanvasRoot: Friendly {
    /// A clipping ancestor: a frame with `clip` on.
    struct Clip: Friendly {
        /// The frame.
        let node: PenNode
        /// Its box and the map from its own coordinates to the canvas.
        let placement: PenPlacement
    }

    /// The root node.
    let node: PenNode

    /// The map from the root's parent's coordinates — the space its layout rect is in — to
    /// the canvas; the identity for a top-level node.
    let parentTransform: PenLayoutEngine.PlaneTransform

    /// The root's clipping ancestors, outermost first.
    let clips: [Clip]

    /// The roots among `ids` the document has, in paint order — the order the canvas draws
    /// them, whatever order they were named in — leaving out any root inside another root,
    /// which its ancestor already draws.
    ///
    /// - Parameters:
    ///   - ids: The root node ids, in the expanded document's spelling.
    ///   - document: The expanded, resolved document.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: The roots; an id the document lacks, or whose ancestors the layout settled
    ///   no rect for, is left out.
    static func resolve(
        _ ids: [String],
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> [PenCanvasRoot] {
        let wanted = Set(ids)
        guard !wanted.isEmpty else { return [] }
        // A work list, not recursion, so a deep tree cannot overflow a Swift task's stack
        // in a debug build (`project/2026-09-26-debug-stack-depth.md`).
        var pending = document.children.reversed().map {
            (node: $0, parent: PenLayoutEngine.PlaneTransform.identity, clips: [Clip]())
        }
        var roots: [PenCanvasRoot] = []
        while let (node, parent, clips) = pending.popLast() {
            if wanted.contains(node.id) {
                roots.append(PenCanvasRoot(node: node, parentTransform: parent, clips: clips))
                continue
            }
            guard let rect = layoutRects[node.id] else { continue }
            let placed = PenLayoutEngine.placement(of: node, rect: rect, layoutRects: layoutRects).placed(in: parent)
            var inner = clips
            if case let .frame(data) = node.kind, data.clip?.literalValue == true {
                inner.append(Clip(node: node, placement: placed))
            }
            pending.append(contentsOf: node.kind.inlineChildren.reversed().map {
                (node: $0, parent: placed.transform, clips: inner)
            })
        }
        return roots
    }
}
