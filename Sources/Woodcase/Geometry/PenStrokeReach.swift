//
//  PenStrokeReach.swift
//  Woodcase
//

import Foundation

/// How far a stroke's band reaches around straight-edged geometry, as bounds — the part
/// of a stroke's painted extent that a plain outset of the geometry gets wrong: a line's
/// caps, and the miters at a sharp polygon's corners.
///
/// `reach` is how far the band extends from the geometry on its outer side: half the
/// width for a centered stroke, the whole width for an outer one (Pen strokes an outer
/// band at twice the width and clips the inside away, so its outline reaches as far).
enum PenStrokeReach {
    /// The miter limit Pen strokes with: Skia's default, the longest miter as a multiple
    /// of the stroke's width before a join falls back to a bevel.
    static let miterLimit = 4.0

    /// The bounds of an open segment's band, with its caps.
    ///
    /// - Parameters:
    ///   - start: The segment's first point.
    ///   - end: Its last point.
    ///   - reach: How far the band extends to each side of the segment.
    ///   - cap: How its ends are capped.
    /// - Returns: The bounds, or `nil` for a segment of no length, which Pen strokes as
    ///   nothing.
    static func openSegment(from start: PenPoint, to end: PenPoint, reach: Double, cap: PenStrokeCap) -> PenRect? {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        if cap == .round {
            return PenRect.bounds(of: [start, end])?.outset(by: reach)
        }
        let along = PenPoint(x: dx / length * reach, y: dy / length * reach)
        let across = PenPoint(x: -along.y, y: along.x)
        let extend = cap == .square ? 1.0 : 0
        let first = PenPoint(x: start.x - along.x * extend, y: start.y - along.y * extend)
        let last = PenPoint(x: end.x + along.x * extend, y: end.y + along.y * extend)
        return PenRect.bounds(of: [first, last].flatMap { point in
            [
                PenPoint(x: point.x + across.x, y: point.y + across.y),
                PenPoint(x: point.x - across.x, y: point.y - across.y),
            ]
        })
    }

    /// The bounds of a closed polyline's band, with its joins.
    ///
    /// At every corner the band has each edge's offset ends; a round join adds a disc of
    /// the reach about the corner, and a miter join the miter's tip, unless the miter is
    /// longer than ``miterLimit`` times the width, where it is beveled.
    ///
    /// - Parameters:
    ///   - points: The corners, in order; the last joins the first.
    ///   - reach: How far the band extends to each side of an edge.
    ///   - join: How corners are joined.
    /// - Returns: The bounds, or `nil` for fewer than two distinct corners.
    static func closedPolyline(_ points: [PenPoint], reach: Double, join: PenStrokeJoin) -> PenRect? {
        guard points.count >= 2 else { return nil }
        var ink: [PenPoint] = []
        for (index, corner) in points.enumerated() {
            let before = points[(index + points.count - 1) % points.count]
            let after = points[(index + 1) % points.count]
            guard let inward = normal(from: before, to: corner), let outward = normal(from: corner, to: after) else {
                continue
            }
            for normal in [inward, outward] {
                ink.append(PenPoint(x: corner.x + normal.x * reach, y: corner.y + normal.y * reach))
                ink.append(PenPoint(x: corner.x - normal.x * reach, y: corner.y - normal.y * reach))
            }
            switch join {
            case .round:
                ink.append(PenPoint(x: corner.x - reach, y: corner.y - reach))
                ink.append(PenPoint(x: corner.x + reach, y: corner.y + reach))
            case .miter:
                // The miter's tip lies along the sum of the two edges' normals, at
                // reach / cos(half the turn); |sum| = 2·cos(half the turn).
                let sum = PenPoint(x: inward.x + outward.x, y: inward.y + outward.y)
                let norm = (sum.x * sum.x + sum.y * sum.y).squareRoot()
                guard norm > 0, 2 / norm <= miterLimit else { continue }
                let scale = 2 * reach / (norm * norm)
                ink.append(PenPoint(x: corner.x + sum.x * scale, y: corner.y + sum.y * scale))
                ink.append(PenPoint(x: corner.x - sum.x * scale, y: corner.y - sum.y * scale))
            case .bevel:
                break
            }
        }
        return PenRect.bounds(of: ink)
    }

    /// The unit normal of the edge from `start` to `end`, or `nil` for an edge of no length.
    private static func normal(from start: PenPoint, to end: PenPoint) -> PenPoint? {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return nil }
        return PenPoint(x: -dy / length, y: dx / length)
    }
}
