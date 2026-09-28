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
    /// its stroke band — nothing for an inner stroke, half the width for a centred one, all
    /// of it for an outer one, per side on a frame or rectangle — then, for a frame that
    /// does not clip and for a group, every enabled child's painted extent carried through
    /// the child's placement. A group paints only its children. Then the effects: each
    /// enabled outer shadow adds a copy of that extent moved by its offset and grown by
    /// 1.5 × its blur (Pen does not count a shadow's spread), and each enabled layer blur
    /// grows the whole by 1.5 × its radius; a background blur and an inner shadow add
    /// nothing. Last, the extent goes through the node's own placement
    /// (``placement(of:rect:layoutRects:)``), corner by corner, so a turned node's band
    /// reaches past its bounds at its mitred corners.
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
}

extension PenLayoutEngine {
    /// A node of the painted-extent walk: the node, its box, the map into its parent's
    /// coordinates, and its parent's index in the walk.
    private struct PaintEntry {
        /// The node.
        let node: PenNode
        /// Its box, in its own coordinates.
        let box: PenRect
        /// The map from its own coordinates to its parent's.
        let transform: PlaneTransform
        /// Its parent's index in the walk; `nil` for the root.
        let parent: Int?
    }

    /// Everything `root` may paint, in its own coordinates, or `nil` when it paints
    /// nothing. See ``paintedExtent(of:rect:layoutRects:)``.
    static func localPaintedExtent(of root: PenNode, box: PenRect, layoutRects: [String: PenRect]) -> PenRect? {
        // A work list, not recursion, so a deep tree cannot overflow a Swift task's stack
        // in a debug build (`project/2026-09-26-debug-stack-depth.md`). Entries are listed
        // parents first, so walking them backwards meets every child before its parent.
        var entries = [PaintEntry(node: root, box: box, transform: .identity, parent: nil)]
        var cursor = 0
        while cursor < entries.count {
            let node = entries[cursor].node
            if paintsChildren(node) {
                for child in node.kind.inlineChildren where child.common.enabled?.literalValue != false {
                    guard let rect = layoutRects[child.id] else { continue }
                    let placement = placement(of: child, rect: rect, layoutRects: layoutRects)
                    entries.append(PaintEntry(
                        node: child, box: placement.box, transform: placement.transform, parent: cursor
                    ))
                }
            }
            cursor += 1
        }

        var children = [PenRect?](repeating: nil, count: entries.count)
        for index in entries.indices.reversed() {
            let entry = entries[index]
            guard let own = union(ownInk(of: entry.node, box: entry.box), children[index]) else { continue }
            let painted = withEffects(own, of: entry.node)
            guard let parent = entry.parent else { return painted }
            children[parent] = union(children[parent], entry.transform.bounds(of: painted))
        }
        return nil
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
    /// blur, and every enabled layer blur then grows the whole by 1.5 × its radius.
    private static func withEffects(_ extent: PenRect, of node: PenNode) -> PenRect {
        guard let effects = PenRenderer.effects(for: node)?.all else { return extent }
        var grown = extent
        for case let .shadow(shadow) in effects
            where shadow.enabled?.literalValue != false && (shadow.shadowType ?? .outer) == .outer
        {
            let reach = 1.5 * max(0, shadow.blur?.literalValue ?? 0)
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
