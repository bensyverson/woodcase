//
//  PenLayoutEngine+AbsoluteRects.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// Every node in the document, in canvas coordinates.
    ///
    /// ``absoluteRects(under:in:layoutRects:)`` for each top-level node, merged: the one
    /// frame a top-level `connection` finds its endpoints in (see
    /// ``PenNode/ConnectionData/segment(in:)``). Both renderers draw connections from it.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: Every node with a settled rect, keyed by id, measured from the canvas
    ///   origin.
    static func canvasRects(
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> [String: PenRect] {
        var rects: [String: PenRect] = [:]
        for node in document.children {
            rects.merge(absoluteRects(under: node.id, in: document, layoutRects: layoutRects)) { first, _ in first }
        }
        return rects
    }

    /// Every node under `rootID`, in the root's own coordinate frame.
    ///
    /// ``layout(_:textMeasurer:)`` settles a rect **relative to the node's parent** — to
    /// its parent's own coordinates: a leaf six levels down reads `x: 0, y: 0` when it sits
    /// at its parent frame's top-left corner, or at its parent group's anchor — and only a
    /// top-level node's rect is in canvas coordinates. ``PenRenderer``
    /// composes those offsets as it descends, so the picture is right; anything that
    /// reads a single rect out of the map and treats it as absolute is not.
    ///
    /// This is that composition, done once. It walks `rootID`'s subtree composing placements
    /// exactly as the renderer's transform stack does, and returns the root together
    /// with every descendant measured from the same origin as the root's own rect. Ask
    /// for a top-level node and the answer is in canvas coordinates; ask for one further
    /// down and the answer is in that node's frame, which is what an overlay drawn over
    /// a render of *that* node wants.
    ///
    /// Being a subtree walk rather than an arithmetic test, membership is also the
    /// answer to *is this node under the root at all*: a node elsewhere in the document
    /// is simply not in the result.
    ///
    /// ## Turned ancestors and groups
    ///
    /// A node's children are measured in its own coordinates, which are not always its
    /// rect's: a turned or flipped node draws its unturned box centred in its rect (the
    /// bounds of the turned box) and turns it about that centre, and a group's children are
    /// measured from its anchor, which its rect — their union — need not start at. So the
    /// walk composes each node's placement (``placement(of:rect:layoutRects:)``: its
    /// ``unturnedBox(of:rect:layoutRects:)`` centred, turned and flipped, as ``PenRenderer``
    /// draws it) down the tree, and answers
    /// with the **axis-aligned bounds** of each node's unturned box under everything above
    /// it. For a node under no turn that is exactly its box; under a turned ancestor its
    /// footprint is a turned quad, and the rect is that quad's bounds — what `shot --outline`
    /// and the viewer's overlay draw. A caller that needs the quad itself maps the box by
    /// ``canvasPlacement(of:in:layoutRects:)``.
    ///
    /// - Parameters:
    ///   - rootID: The root of the walk, in the expanded document's spelling — see
    ///     ``EditableDocument/expandedID(of:)``.
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: `rootID` and each of its descendants, keyed by id, with `x`/`y`
    ///   measured from the same origin as the root's own rect. Each is plain bounds, with
    ///   no ``PenRect/unturnedSize``: under a turned ancestor a box's footprint is not one
    ///   turn of it, and the layout rect already carries the node's own. Empty when the document
    ///   has no such node, or the layout engine settled no rect for it. A descendant the
    ///   engine settled no rect for is dropped, and so is everything beneath it.
    static func absoluteRects(
        under rootID: String,
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> [String: PenRect] {
        guard let root = node(id: rootID, in: document.children),
              let rootRect = layoutRects[rootID]
        else { return [:] }

        // Both walks run from work lists, not recursion, so a deep tree cannot overflow
        // a Swift task's stack in a debug build (`project/2026-09-26-debug-stack-depth.md`).
        // Every answer is plain bounds; only a layout rect carries an unturned size.
        var frame: [String: PenRect] = [rootID: rootRect.bounds]
        let rootPlacement = placement(of: root, rect: rootRect, layoutRects: layoutRects)
        var pending = root.kind.inlineChildren.reversed().map { (node: $0, parent: rootPlacement.transform) }
        while let (node, parent) = pending.popLast() {
            guard let relative = layoutRects[node.id] else { continue }
            let placed = placement(of: node, rect: relative, layoutRects: layoutRects).placed(in: parent)
            frame[node.id] = placed.bounds
            pending.append(contentsOf: node.kind.inlineChildren.reversed().map { (node: $0, parent: placed.transform) })
        }
        return frame
    }

    /// The first node in pre-order with the given id, found without recursion.
    static func node(id: String, in nodes: [PenNode]) -> PenNode? {
        var pending = Array(nodes.reversed())
        while let node = pending.popLast() {
            if node.id == id { return node }
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
        }
        return nil
    }
}
