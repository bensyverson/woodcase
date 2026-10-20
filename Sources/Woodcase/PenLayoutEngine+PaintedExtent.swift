//
//  PenLayoutEngine+PaintedExtent.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// Everything a node may paint, in its parent's coordinates — extent (iii), the one
    /// Pen frames an export on.
    ///
    /// Pen's `getVisualLocalBounds`, reproduced: in the node's own coordinates, its
    /// geometry (the box, or a path's or polygon's own outline) and
    /// its stroke band — nothing for an inner stroke, half the width for a centered one, all
    /// of it for an outer one, per side on a frame or rectangle — then, for a frame that
    /// does not clip and for a group, every enabled child's painted extent carried through
    /// the child's placement. A group paints only its children. Then the effects: each
    /// enabled outer shadow adds a copy of that extent moved by its offset and grown by
    /// 1.5 × its blur and by its spread (``PenNode/shadowSpread(forEffect:)``, which Pen
    /// neither keeps in the format nor draws, but Woodcase draws), and each enabled layer blur
    /// grows the whole by 1.5 × its radius; a background blur and an inner shadow add
    /// nothing. A note's or prompt's paper casts its look's shadows
    /// (``PenPostIt/Style/shadows``) as if they were its effects. Last, the extent goes through the node's own placement
    /// (``placement(of:rect:layoutRects:)``), corner by corner, so a turned node's band
    /// reaches past its bounds at its mitered corners.
    ///
    /// Strokes, shadows and blur never enter layout (`project/2026-09-28-geometry-model.md`):
    /// this is what an export, a `shot --extent painted`, a culling pass or an invalidated
    /// region needs, never what a parent allocates. Readers: the render-test helpers that
    /// place Pen's reference images, `shot --extent painted`, RapidPro's culling and
    /// Penumbra's stroke-band hit test.
    ///
    /// A text counts its glyphs' tight ink (``textInkBounds(of:box:)``), modulo the Core
    /// Text/Skia glyph-metric gap `PenGoogleFonts.md` documents for Inter at these sizes.
    /// An icon counts its fitted glyph's ink too (``iconInkBounds(of:box:)``), modulo a
    /// wider font-substitution gap for at least one bundled icon (Woodcase's installed
    /// icon font vs. Pen's own bundled vector set do not always draw the same shape for
    /// the same name). A sharp corner of a path's stroke counts only the band's half
    /// width, where Pen counts its miter.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - rect: Its layout rect, in its parent's coordinates.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them, for
    ///     its descendants.
    /// - Returns: The painted extent, in the parent's coordinates. A node that paints
    ///   nothing at all — a group with no enabled child — answers an empty rect at its
    ///   bounds' corner.
    static func paintedExtent(of node: PenNode, rect: PenRect, layoutRects: [String: PenRect]) -> PenRect {
        let placement = placement(of: node, rect: rect, layoutRects: layoutRects)
        return mapped(localPaintedExtent(of: node, box: placement.box, layoutRects: layoutRects), by: placement)
    }

    /// Every node's painted extent in a subtree, from one walk: for the root and for each
    /// descendant the layout placed, exactly what ``paintedExtent(of:rect:layoutRects:)``
    /// answers for it, in its own parent's coordinates.
    ///
    /// A node's painted extent folds in its unclipped descendants', so asking for each
    /// node in turn measures a text's ink again for every unclipped ancestor above it.
    /// This walks the subtree once and computes each node's extent on the way up from its
    /// children's, so each text's ink is measured once — what a renderer's culling bounds
    /// or an editor's hit shapes need for every node of a run.
    ///
    /// A clipping frame's descendants and a disabled node still get their own extents —
    /// the table answers every placed node, as ``paintedExtent(of:rect:layoutRects:)``
    /// would — but neither reaches its parent's.
    ///
    /// - Parameters:
    ///   - root: The subtree's root.
    ///   - rect: Its layout rect, in its parent's coordinates.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them, for
    ///     its descendants.
    /// - Returns: The painted extents by node id: the root's, and every descendant's whose
    ///   rect and ancestors' rects up to the root were settled. A later node with a
    ///   repeated id overwrites an earlier one; an expanded document repeats none.
    static func paintedExtents(of root: PenNode, rect: PenRect, layoutRects: [String: PenRect]) -> [String: PenRect] {
        let walk = PaintWalk(
            root: root, placement: placement(of: root, rect: rect, layoutRects: layoutRects),
            layoutRects: layoutRects, reach: .everyPlacedDescendant
        )
        var extents = [String: PenRect](minimumCapacity: walk.entries.count)
        for (entry, painted) in zip(walk.entries, walk.painted) {
            extents[entry.node.id] = mapped(painted, by: entry.placement)
        }
        return extents
    }

    /// Every node's painted extent in a laid-out document, from one walk per top-level
    /// node: ``paintedExtents(of:rect:layoutRects:)`` for each root the layout placed.
    ///
    /// - Parameters:
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: The painted extents by node id, each in its parent's coordinates, for
    ///   every node with a rect whose ancestors all have one.
    static func paintedExtents(in document: PenDocument, layoutRects: [String: PenRect]) -> [String: PenRect] {
        var extents: [String: PenRect] = [:]
        for root in document.children {
            guard let rect = layoutRects[root.id] else { continue }
            extents.merge(paintedExtents(of: root, rect: rect, layoutRects: layoutRects)) { $1 }
        }
        return extents
    }

    /// Everything a node may paint, in canvas coordinates:
    /// ``paintedExtent(of:rect:layoutRects:)``'s own-coordinates extent carried through
    /// ``canvasPlacement(of:in:layoutRects:)`` in one step, as Pen's
    /// `getVisualWorldBounds` does — so a node under a turned ancestor answers the bounds
    /// of its own ink turned, not of its parent-relative extent's bounds turned again.
    ///
    /// - Parameters:
    ///   - nodeID: The node, in the expanded document's spelling — see
    ///     ``EditableDocument/expandedID(of:)``.
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: The painted extent on the canvas, or `nil` when the document has no such
    ///   node, or the layout settled no rect for it or for one of its ancestors.
    static func canvasPaintedExtent(
        of nodeID: String,
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> PenRect? {
        guard let node = node(id: nodeID, in: document.children),
              let placement = canvasPlacement(of: nodeID, in: document, layoutRects: layoutRects)
        else { return nil }
        return mapped(localPaintedExtent(of: node, box: placement.box, layoutRects: layoutRects), by: placement)
    }

    /// Everything a selection may paint, in canvas coordinates: the union of each node's
    /// ``canvasPaintedExtent(of:in:layoutRects:)``. The bounds that hold a multi-root PNG
    /// or SVG of the selection whole, shadows and overhangs included.
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes, in the expanded document's spelling.
    ///   - document: The expanded, resolved document the layout ran on.
    ///   - layoutRects: The settled rects, parent-relative as the engine writes them.
    /// - Returns: The union, or `nil` when no id names a node with a settled rect.
    static func canvasPaintedExtent(
        of nodeIDs: [String],
        in document: PenDocument,
        layoutRects: [String: PenRect]
    ) -> PenRect? {
        nodeIDs.reduce(nil) { extent, id in
            union(extent, canvasPaintedExtent(of: id, in: document, layoutRects: layoutRects))
        }
    }
}

extension PenLayoutEngine {
    /// Everything `root` may paint, in its own coordinates, or `nil` when it paints
    /// nothing. See ``paintedExtent(of:rect:layoutRects:)``.
    static func localPaintedExtent(of root: PenNode, box: PenRect, layoutRects: [String: PenRect]) -> PenRect? {
        PaintWalk(
            root: root, placement: PenPlacement(box: box, transform: .identity),
            layoutRects: layoutRects, reach: .paintingDescendants
        ).painted[0]
    }

    /// One bottom-up painted-extent walk of a subtree: each node's own ink, grown by the
    /// extents of the children that paint into it, then by its effects — the one copy of
    /// the rules ``paintedExtent(of:rect:layoutRects:)`` documents, which both it and
    /// ``paintedExtents(of:rect:layoutRects:)`` read.
    private struct PaintWalk {
        /// Which descendants a walk visits.
        enum Reach: Friendly {
            /// Only those that paint into the root's extent: what one node's extent needs.
            case paintingDescendants
            /// Every descendant the layout placed, painting into the root's extent or not:
            /// what a table of every node's extent needs.
            case everyPlacedDescendant
        }

        /// A node of the walk.
        struct Entry {
            /// The node.
            let node: PenNode
            /// Its box, in its own coordinates, and the map into its parent's.
            let placement: PenPlacement
            /// Its parent's index in the walk; `nil` for the root.
            let parent: Int?
            /// Whether its extent paints into its parent's: it is enabled and its parent
            /// paints its children (``paintsChildren(_:)``).
            let paintsIntoParent: Bool
        }

        /// The nodes, parents before children, the root first.
        let entries: [Entry]

        /// Each entry's painted extent in its own coordinates, or `nil` when it paints
        /// nothing.
        let painted: [PenRect?]

        /// Walks a subtree.
        ///
        /// - Parameters:
        ///   - root: The subtree's root.
        ///   - placement: Its placement; only its box is read for the root's extent.
        ///   - layoutRects: The settled rects of its descendants.
        ///   - reach: Which descendants to visit.
        init(root: PenNode, placement: PenPlacement, layoutRects: [String: PenRect], reach: Reach) {
            // A work list, not recursion, so a deep tree cannot overflow a Swift task's
            // stack in a debug build (`project/2026-09-26-debug-stack-depth.md`). Entries
            // are listed parents first, so walking them backwards meets every child before
            // its parent — and each parent's children in the same order, whichever the
            // reach, so a node's extent is the same to the bit from either walk.
            var entries = [Entry(node: root, placement: placement, parent: nil, paintsIntoParent: false)]
            var cursor = 0
            while cursor < entries.count {
                let node = entries[cursor].node
                let paints = PenLayoutEngine.paintsChildren(node)
                if paints || reach == .everyPlacedDescendant {
                    for child in node.kind.inlineChildren {
                        let enabled = child.common.enabled?.literalValue != false
                        guard enabled || reach == .everyPlacedDescendant, let rect = layoutRects[child.id] else {
                            continue
                        }
                        entries.append(Entry(
                            node: child,
                            placement: PenLayoutEngine.placement(of: child, rect: rect, layoutRects: layoutRects),
                            parent: cursor,
                            paintsIntoParent: paints && enabled
                        ))
                    }
                }
                cursor += 1
            }

            var children = [PenRect?](repeating: nil, count: entries.count)
            var painted = [PenRect?](repeating: nil, count: entries.count)
            for index in entries.indices.reversed() {
                let entry = entries[index]
                let own = PenLayoutEngine.union(
                    PenLayoutEngine.ownInk(of: entry.node, box: entry.placement.box), children[index]
                )
                guard let own else { continue }
                let extent = PenLayoutEngine.withEffects(own, of: entry.node)
                painted[index] = extent
                guard let parent = entry.parent, entry.paintsIntoParent else { continue }
                children[parent] = PenLayoutEngine.union(children[parent], entry.placement.transform.bounds(of: extent))
            }
            self.entries = entries
            self.painted = painted
        }
    }

    /// Whether a node's children paint into its extent: a group's always, a frame's
    /// unless it clips them.
    private static func paintsChildren(_ node: PenNode) -> Bool {
        switch node.kind {
        case .group: true
        case let .frame(data): data.clip?.literalValue != true
        default: false
        }
    }

    /// `extent` grown by a node's effects, as Pen grows it: every enabled outer shadow adds
    /// a copy of the extent before any shadow, moved by its offset and grown by 1.5 × its
    /// blur and by any positive spread Woodcase draws for it, and every enabled layer blur
    /// then grows the whole by 1.5 × its radius.
    private static func withEffects(_ extent: PenRect, of node: PenNode) -> PenRect {
        guard let effects = PenRenderer.effects(for: node)?.all ?? PenPostIt.paperEffects(of: node) else { return extent }
        var grown = extent
        for (index, effect) in effects.enumerated() {
            guard case let .shadow(shadow) = effect, shadow.enabled?.literalValue != false,
                  (shadow.shadowType ?? .outer) == .outer
            else { continue }
            let reach = 1.5 * max(0, shadow.blur?.literalValue ?? 0) + max(0, node.shadowSpread(forEffect: index) ?? 0)
            let moved = PenRect(
                x: extent.x + (shadow.offset?.x.literalValue ?? 0),
                y: extent.y + (shadow.offset?.y.literalValue ?? 0),
                width: extent.width, height: extent.height
            )
            grown = grown.union(moved.outset(by: reach))
        }
        for case let .blur(blur) in effects where blur.enabled?.literalValue != false {
            grown = grown.outset(by: 1.5 * max(0, blur.radius?.literalValue ?? 0))
        }
        return grown
    }

    /// The union of two optional extents.
    private static func union(_ lhs: PenRect?, _ rhs: PenRect?) -> PenRect? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs.union(rhs)
    }

    /// A local extent carried into a placement's space; nothing painted is an empty rect
    /// at the placement's bounds' corner.
    private static func mapped(_ local: PenRect?, by placement: PenPlacement) -> PenRect {
        guard let local else {
            let bounds = placement.bounds
            return PenRect(x: bounds.x, y: bounds.y, width: 0, height: 0)
        }
        return placement.transform.bounds(of: local)
    }
}
