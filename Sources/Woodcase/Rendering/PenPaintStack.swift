//
//  PenPaintStack.swift
//  Woodcase
//

/// A node's own paints in the order they draw — its fills bottom to top, then its stroke's
/// paints bottom to top — the stack a paint's blend mode blends within.
///
/// A paint's blend mode blends only with the paints beneath it in this stack, and the stack
/// is composited as one isolated group, so it never blends with what lies behind the node;
/// only the node's own blend mode (``PenNode/blendMode``) reaches the backdrop (Ben's
/// "reading 1" ruling, 2026-10-20). It is CSS's model: `background-blend-mode` layers do not
/// blend with the content behind the element; `mix-blend-mode` on the element does. Pen
/// differs: its renderer blends a paint with whatever lies behind the node, so a blended
/// paint lowest in its stack — which here blends with nothing — draws differently there
/// (``lowestBlend``, and the `paint-blend-lowest` lint).
struct PenPaintStack: Friendly {
    /// Where a paint sits in the stack.
    enum Place: Friendly {
        /// The fill at this index of the node's fills, as listed (disabled ones counted).
        case fill(Int)
        /// The stroke paint at this index of the node's stroke, as listed.
        case stroke(Int)
    }

    /// The node's fills, bottom to top, as listed.
    let fills: [PenFill]
    /// The node's stroke paints, bottom to top, as listed.
    let strokes: [PenFill]

    /// A stack of `fills` under `strokes`.
    ///
    /// - Parameters:
    ///   - fills: The fills; `nil` for none.
    ///   - strokes: The stroke's paints; `nil` for none.
    init(fills: PenFills?, strokes: PenFills?) {
        self.fills = fills?.all ?? []
        self.strokes = strokes?.all ?? []
    }

    /// The stack `node` draws: its fills — or `overrideFills`, an animation's, in their
    /// place — and its stroke, for the kinds that draw one.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - overrideFills: Fills that replace the node's own, or `nil`.
    init(_ node: PenNode, overrideFills: PenFills? = nil) {
        self.init(fills: overrideFills ?? PenRenderer.fills(for: node), strokes: PenRenderer.strokePaints(for: node))
    }

    /// Every paint that draws, with its place, bottom first.
    var drawn: [(place: Place, paint: PenFill)] {
        let fillPaints = fills.enumerated().map { (place: Place.fill($0.offset), paint: $0.element) }
        let strokePaints = strokes.enumerated().map { (place: Place.stroke($0.offset), paint: $0.element) }
        return (fillPaints + strokePaints).filter(\.paint.isEnabled)
    }

    /// Whether any drawn paint blends: its mode draws otherwise than normal.
    var blends: Bool {
        drawn.contains { $0.paint.blendMode?.blends == true }
    }

    /// Whether any drawn paint blends by a mode the renderer composites per pixel.
    var blendsPerPixel: Bool {
        drawn.contains { $0.paint.blendMode.map { $0.blends && $0.compositing == .perPixel } ?? false }
    }

    /// The lowest drawn paint's place and mode when it blends — the paint whose blend blends
    /// with nothing here, where Pen blends it with what lies behind the node — or `nil`.
    var lowestBlend: (place: Place, mode: PenBlendMode)? {
        guard let lowest = drawn.first, let mode = lowest.paint.blendMode, mode.blends else { return nil }
        return (lowest.place, mode)
    }
}
