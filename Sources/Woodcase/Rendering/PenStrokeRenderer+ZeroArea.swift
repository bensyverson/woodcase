//
//  PenStrokeRenderer+ZeroArea.swift
//  Woodcase
//

import CoreGraphics

extension PenStrokeRenderer {
    /// The band a uniform stroke covers on a box that is a point — 0×0 — or `nil` when the
    /// box has extent on either axis (or there is no box), and stroking the shape's path is
    /// right.
    ///
    /// A `layout: "none"` frame with no size settles at 0×0, and Pen still paints its stroke
    /// around the point: an 8 pt outer stroke is a 16×16 square, and its outer shadow is
    /// cast by that square (`render-sizeless-frames.pen`, board `paint`). Core Graphics
    /// strokes nothing along a path of no length, so the band is laid out from the box the
    /// way a per-side stroke's is (``perSideRing(widths:alignment:box:)``), all four sides
    /// at `width`. A box flat on one axis only is left to the path's stroke: Pen has not
    /// been measured there.
    ///
    /// - Parameters:
    ///   - width: The stroke's width, in points.
    ///   - alignment: Where the band sits against the box's edges.
    ///   - box: The node's box, when it is box-shaped (``roundedBox(for:rect:)``).
    /// - Returns: The band, to fill even-odd.
    static func zeroAreaBand(width: CGFloat, alignment: PenStrokeAlign, box: RoundedBox?) -> CGPath? {
        guard let box, box.rect.width <= 0, box.rect.height <= 0 else { return nil }
        return perSideRing(widths: SideWidths(uniform: width), alignment: alignment, box: box)
    }
}

extension PenStrokeRenderer.SideWidths {
    /// The same width on every side.
    ///
    /// - Parameter width: Each side's width, in points.
    init(uniform width: CGFloat) {
        top = width
        right = width
        bottom = width
        left = width
    }
}
