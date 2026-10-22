//
//  SwiftUINodeEmitter+PaintIsolation.swift
//  Woodcase
//

extension SwiftUINodeEmitter {
    /// Whether a node's paints must be composited as a group of their own —
    /// `.compositingGroup()` — so that a blended paint stays within them.
    ///
    /// A paint blends only with the paints beneath it on its node, fills then strokes, and
    /// never with what lies behind the node (Ben's reading-1 ruling, 2026-10-20;
    /// `PenPaintStack`), as the renderer draws a blended stack in an isolated group. A
    /// SwiftUI `.blendMode` reaches whatever is composited beneath it, so a stack that blends
    /// is grouped — except where its lowest fill is an opaque color of normal blend
    /// (``SwiftUIPaintLayer/covers``) and only fills blend: they then blend only with what
    /// that color covers. The lowest paint's own blend is never written
    /// (``paintLayers(_:box:of:overPaints:unemitted:)``).
    ///
    /// - Parameters:
    ///   - fills: The node's fill layers.
    ///   - stroke: The stroke it draws, or `nil` when it draws none.
    func isolatesPaints(fills: [SwiftUIPaintLayer], stroke: (any PenStrokable)?) -> Bool {
        let fillsBlend = fills.contains { $0.blendMode != nil } && fills.first?.covers != true
        return fillsBlend || strokeBlends(stroke, over: fills)
    }

    /// Whether a stroke's paints blend once drawn over `fills`: any enabled paint at a mode
    /// SwiftUI writes, its lowest left out when there are no fills beneath it, as
    /// ``strokeView(_:shape:box:dash:miterLimit:overFills:unemitted:)`` leaves its blend out.
    ///
    /// Read from the paints rather than their layers, whose colors the theme counts as it
    /// reads them. A paint an opaque one above it hides still counts here, which costs at
    /// most a group that changes nothing.
    func strokeBlends(_ stroke: (any PenStrokable)?, over fills: [SwiftUIPaintLayer]) -> Bool {
        let paints = (stroke?.stroke?.all ?? []).filter(\.isEnabled).dropFirst(fills.isEmpty ? 1 : 0)
        return paints.contains { paint in
            paint.blendMode.map { $0.blends && SwiftUIBlendMode.name(for: $0) != nil } ?? false
        }
    }
}
