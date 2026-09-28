//
//  PenLayoutEngine+OwnInk.swift
//  Woodcase
//

import Foundation

public extension PenLayoutEngine {
    /// What a node paints itself, before its children and effects, in its own
    /// coordinates: its geometry and its stroke band; `nil` for a group, which paints only
    /// its children.
    ///
    /// Pen's per-kind `computeVisualLocalBounds`: a frame starts from its box, a shape from
    /// its fill path's bounds — a polygon's vertices, a path's outline wherever its
    /// `viewBox` carries it, inside the box or out — a text from its glyphs' tight ink
    /// (``textInkBounds(of:box:)``, from its own Skia fill path), an icon from its glyph's
    /// tight ink too (``iconInkBounds(of:box:)``, from its own vector fill path fitted to
    /// the box and centred), and every other node from its box. The stroke band is Pen's
    /// (`DZt`): nothing for an inner stroke; a frame's or a rectangle's box grown per side
    /// by the side's width, halved for a centred stroke; any other shape stroked at its
    /// top width, its band reaching past the geometry by the same half or whole width,
    /// with a line's caps and a sharp polygon's joins counted. Neither a text's nor an
    /// icon's stroke is counted: Pen bounds both by their glyphs alone.
    ///
    /// This is the *reach* of a node's stroke band as a bounding rect — cheap, and what
    /// ``paintedExtent(of:rect:layoutRects:)`` composes into an extent. A caller that
    /// needs to know whether one exact point falls *inside* that band — Penumbra's
    /// selection, which hits the turned box, then the stroke band, as Pen does — wants
    /// ``strokeBandContains(_:of:box:)`` instead, which tests the true stroked outline,
    /// not this rect.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - box: Its box, in its own coordinates (``unturnedBox(of:rect:layoutRects:)``).
    /// - Returns: The extent, or `nil` for a group.
    static func ownInk(of node: PenNode, box: PenRect) -> PenRect? {
        if case .group = node.kind { return nil }
        let geometry = fillBounds(of: node, box: box)
        guard let band = strokeBand(of: node, box: box, geometry: geometry) else { return geometry }
        return geometry.union(band)
    }

    /// The bounds of a node's fill geometry: a path's outline as mapped onto its box, a
    /// polygon's vertices, a text's or an icon's glyph ink, and the box for everything else.
    private static func fillBounds(of node: PenNode, box: PenRect) -> PenRect {
        switch node.kind {
        case let .path(data):
            guard let geometry = data.geometry, let path = PenPath(svg: geometry),
                  let bounds = path.mapped(onto: box, viewBox: data.viewBox).tightBounds
            else { return box }
            return bounds
        case .polygon:
            return polygonVertices(of: node, box: box).flatMap(PenRect.bounds(of:)) ?? box
        case let .text(data):
            // `nil` (no content) keeps the box: an empty text node has nothing Pen would
            // paint differently, and the box is still a rect worth pointing at.
            return textInkBounds(of: data, box: box) ?? box
        case let .icon(data):
            // `nil` (no library, no icon, or an unresolvable one) keeps the box, for the
            // same reason: nothing paints differently there.
            return iconInkBounds(of: data, box: box) ?? box
        default:
            return box
        }
    }

    /// The bounds of a node's stroke band, or `nil` when it has no stroke that paints
    /// outside its geometry.
    private static func strokeBand(of node: PenNode, box: PenRect, geometry: PenRect) -> PenRect? {
        guard let stroke = strokable(node)?.drawn(on: node),
              stroke.stroke?.hasVisiblePaint == true
        else { return nil }
        let alignment = stroke.strokeAlignment ?? .center
        guard alignment != .inner else { return nil }
        let share = alignment == .center ? 0.5 : 1

        switch node.kind {
        case .frame, .rectangle, .browser:
            let sides = sideWidths(stroke)
            guard sides.top > 0 || sides.right > 0 || sides.bottom > 0 || sides.left > 0 else { return nil }
            return box.outset(
                top: sides.top * share, right: sides.right * share,
                bottom: sides.bottom * share, left: sides.left * share
            )
        default:
            guard let width = stroke.uniformStrokeWidth, width > 0 else { return nil }
            let reach = width * share
            switch node.kind {
            case .line:
                return lineBand(in: box, reach: reach, cap: stroke.strokeLinecap ?? .butt)
            case .polygon:
                guard polygonIsSharp(node), let vertices = polygonVertices(of: node, box: box) else {
                    return geometry.outset(by: reach)
                }
                return PenStrokeReach.closedPolyline(vertices, reach: reach, join: stroke.strokeLinejoin ?? .miter)
            default:
                return geometry.outset(by: reach)
            }
        }
    }

    /// A node's stroke keys, for the kinds whose stroke Pen counts in its painted extent —
    /// shared with ``strokeBandContains(_:of:box:)``, which needs the same list. A text's
    /// or an icon's stroke is not counted: Pen bounds both by their glyphs alone.
    ///
    /// Module-internal, not `private`: the enclosing extension is `public`, and this stays
    /// out of the public surface only because it says so explicitly.
    internal static func strokable(_ node: PenNode) -> (any PenStrokable)? {
        switch node.kind {
        case let .frame(data): data
        case let .rectangle(data): data
        case let .browser(data): data
        case let .ellipse(data): data
        case let .polygon(data): data
        case let .path(data): data
        case let .line(data): data
        default: nil
        }
    }

    /// A stroke's width on each side: its per-side widths, a missing side 0, or its uniform
    /// width on all four.
    private static func sideWidths(_ stroke: some PenStrokable) -> (top: Double, right: Double, bottom: Double, left: Double) {
        if case let .perSide(sides) = stroke.strokeWidth {
            return (
                max(0, sides.top?.literalValue ?? 0), max(0, sides.right?.literalValue ?? 0),
                max(0, sides.bottom?.literalValue ?? 0), max(0, sides.left?.literalValue ?? 0)
            )
        }
        let width = max(0, stroke.uniformStrokeWidth ?? 0)
        return (width, width, width, width)
    }

    /// The band of a line from the box's top-left corner to its bottom-right, with its caps.
    private static func lineBand(in box: PenRect, reach: Double, cap: PenStrokeCap) -> PenRect? {
        let start = PenPoint(x: box.x, y: box.y), end = PenPoint(x: box.maxX, y: box.maxY)
        return PenStrokeReach.openSegment(from: start, to: end, reach: reach, cap: cap)
    }

    /// Whether a polygon's corners are sharp — it rounds none of them.
    private static func polygonIsSharp(_ node: PenNode) -> Bool {
        guard case let .polygon(data) = node.kind else { return false }
        return (data.cornerRadius?.resolve()?.topLeft ?? 0) <= 0
    }

    /// A polygon's vertices inscribed in its box, as ``PenShapeGeometry`` draws them.
    private static func polygonVertices(of node: PenNode, box: PenRect) -> [PenPoint]? {
        guard case let .polygon(data) = node.kind else { return nil }
        let sides = data.polygonCount?.literalValue.map { Int($0) } ?? PenShapeGeometry.defaultPolygonCount
        return PenShapeGeometry.polygonVertices(in: box.standardized, sides: sides)
    }
}
