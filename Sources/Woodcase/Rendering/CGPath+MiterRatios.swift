//
//  CGPath+MiterRatios.swift
//  Woodcase
//

import CoreGraphics

extension CGPath {
    /// The miter length of every corner the path turns, as a multiple of the stroke's width:
    /// 1 / sin(θ / 2) at a corner of interior angle θ. A miter join is beveled where this
    /// exceeds the miter limit, so these say which limits draw the path alike.
    ///
    /// A corner is where one segment's end tangent meets the next one's start tangent,
    /// within a subpath and, for a closed subpath, where it closes; a curve's tangents are
    /// read from its control points. A smooth join or a straight run is 1.
    var miterRatios: [Double] {
        var ratios: [Double] = []
        var start: CGPoint?
        var current = CGPoint.zero
        var firstTangent: CGPoint?
        var lastTangent: CGPoint?

        func join(_ incoming: CGPoint?, _ outgoing: CGPoint?) {
            guard let incoming, let outgoing,
                  let a = Self.unit(incoming), let b = Self.unit(outgoing)
            else { return }
            // The interior angle θ is π minus the turn φ, so sin(θ / 2) = cos(φ / 2), and a
            // full reversal (φ = π) has no miter to speak of.
            let cosTurn = max(-1, min(1, a.x * b.x + a.y * b.y))
            let cosHalfTurn = ((1 + cosTurn) / 2).squareRoot()
            guard cosHalfTurn > 1e-9 else { return }
            ratios.append(1 / cosHalfTurn)
        }

        func segment(to end: CGPoint, startTangent: CGPoint, endTangent: CGPoint) {
            join(lastTangent, startTangent)
            if firstTangent == nil { firstTangent = startTangent }
            lastTangent = endTangent
            current = end
        }

        applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                start = points[0]
                current = points[0]
                firstTangent = nil
                lastTangent = nil
            case .addLineToPoint:
                let end = points[0]
                let tangent = CGPoint(x: end.x - current.x, y: end.y - current.y)
                segment(to: end, startTangent: tangent, endTangent: tangent)
            case .addQuadCurveToPoint:
                let control = points[0], end = points[1]
                segment(
                    to: end,
                    startTangent: CGPoint(x: control.x - current.x, y: control.y - current.y),
                    endTangent: CGPoint(x: end.x - control.x, y: end.y - control.y)
                )
            case .addCurveToPoint:
                let first = points[0], second = points[1], end = points[2]
                segment(
                    to: end,
                    startTangent: CGPoint(x: first.x - current.x, y: first.y - current.y),
                    endTangent: CGPoint(x: end.x - second.x, y: end.y - second.y)
                )
            case .closeSubpath:
                if let start, start != current {
                    let tangent = CGPoint(x: start.x - current.x, y: start.y - current.y)
                    segment(to: start, startTangent: tangent, endTangent: tangent)
                }
                join(lastTangent, firstTangent)
                lastTangent = nil
                firstTangent = nil
            @unknown default:
                break
            }
        }
        return ratios
    }

    /// `vector` scaled to unit length, or `nil` for no length.
    private static func unit(_ vector: CGPoint) -> CGPoint? {
        let length = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        guard length > 1e-12 else { return nil }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }
}
