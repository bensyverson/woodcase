//
//  PenLayoutEngine+StrokeBandHitTest.swift
//  Woodcase
//

import CoreGraphics
import Foundation

public extension PenLayoutEngine {
    /// Whether `point` falls inside a node's stroke band — the true stroked outline, not
    /// ``ownInk(of:box:)``'s bounding rect of it.
    ///
    /// Pen hits the band with `strokePath.containsPoint`; this builds the same shape a CG
    /// render actually strokes (``PenShapeBuilder/buildPath(for:rect:)`` run through
    /// `CGPath.copy(strokingWithWidth:lineCap:lineJoin:miterLimit:)`, exactly as
    /// ``PenStrokeRenderer`` paints one) and tests the point against it, so a click just
    /// outside a rounded corner's true curve — inside its naive bounding box, but not
    /// inside the corner itself — correctly misses.
    ///
    /// Alignment changes what "inside the band" means, not the outline's width alone: a
    /// centred stroke's doubled-width outline already *is* the band; an inner or outer
    /// stroke's is cut to the half that alignment keeps, against the shape's own fill
    /// (`PenStrokeRenderer.renderPainted`'s clip, read back as a test instead of a draw).
    /// A line has no fill to cut against, so its band ignores alignment and is always
    /// centred on the segment, with its own caps — matching
    /// ``Woodcase/PenLayoutEngine/ownInk(of:box:)``'s treatment of a line's *reach*, which
    /// this generalizes from a bounding rect to the true capsule.
    ///
    /// A per-side stroke on a box-shaped node (a frame, a rectangle or a browser node) is
    /// tested against its own ring (`PenStrokeRenderer.perSideRing(widths:alignment:box:)`)
    /// rather than the uniform-width path above.
    ///
    /// - Parameters:
    ///   - point: The point to test, in the node's own coordinates — the same space `box`
    ///     is in, not the canvas or a turned ancestor's.
    ///   - node: The node.
    ///   - box: Its box, in its own coordinates (``unturnedBox(of:rect:layoutRects:)``).
    /// - Returns: `true` when `point` is in the band a visible stroke actually paints;
    ///   `false` for a node with no stroke, an invisible one, or one whose paint is
    ///   disabled — the same gate ``ownInk(of:box:)`` uses.
    static func strokeBandContains(_ point: PenPoint, of node: PenNode, box: PenRect) -> Bool {
        guard let stroke = strokable(node)?.drawn(on: node), stroke.stroke?.hasVisiblePaint == true
        else { return false }
        let cgPoint = point.cgPoint

        if case .line = node.kind {
            return lineBandContains(cgPoint, stroke: stroke, box: box)
        }

        if case let .perSide(sides) = stroke.strokeWidth,
           let roundedBox = PenStrokeRenderer.roundedBox(for: node, rect: box)
        {
            let widths = PenStrokeRenderer.SideWidths(sides)
            guard !widths.isEmpty else { return false }
            let ring = PenStrokeRenderer.perSideRing(
                widths: widths, alignment: stroke.strokeAlignment ?? .center, box: roundedBox
            )
            return ring.contains(cgPoint, using: .evenOdd)
        }

        guard let width = stroke.uniformStrokeWidth, width > 0,
              let path = PenShapeBuilder.buildPath(for: node, rect: box)
        else { return false }
        let alignment = stroke.strokeAlignment ?? .center
        let style = PenStrokeRenderer.Style(
            width: CGFloat(width), alignment: alignment,
            penJoin: stroke.strokeLinejoin, penCap: stroke.strokeLinecap
        )
        let outline = path.copy(
            strokingWithWidth: style.outlineWidth, lineCap: style.cap, lineJoin: style.join,
            miterLimit: PenStrokeRenderer.Style.miterLimit
        )
        guard outline.contains(cgPoint, using: .winding) else { return false }
        switch alignment {
        case .center: return true
        case .inner: return path.contains(cgPoint)
        case .outer: return !path.contains(cgPoint)
        }
    }

    /// A line's band: the true stroked capsule of the segment from the box's top-left
    /// corner to its bottom-right, with `strokeLinecap`'s caps. Alignment plays no part —
    /// a line has no interior for "inner" or "outer" to cut against, so its band is
    /// always centred on the segment, as ``ownInk(of:box:)``'s `lineBand` already treats
    /// its bounding rect.
    private static func lineBandContains(_ point: CGPoint, stroke: any PenStrokable, box: PenRect) -> Bool {
        guard let width = stroke.uniformStrokeWidth, width > 0 else { return false }
        let segment = CGMutablePath()
        segment.move(to: CGPoint(x: box.x, y: box.y))
        segment.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        let cap: CGLineCap = switch stroke.strokeLinecap {
        case .round: .round
        case .square: .square
        case .butt, nil: .butt
        }
        let outline = segment.copy(
            strokingWithWidth: CGFloat(width), lineCap: cap, lineJoin: .miter,
            miterLimit: PenStrokeRenderer.Style.miterLimit
        )
        return outline.contains(point)
    }
}
