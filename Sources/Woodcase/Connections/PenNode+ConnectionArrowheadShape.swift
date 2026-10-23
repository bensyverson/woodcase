//
//  PenNode+ConnectionArrowheadShape.swift
//  Woodcase
//

import Foundation

public extension PenNode.ConnectionData.Arrowhead {
    /// An arrowhead as geometry on the canvas, painted with the connection's stroke paint.
    ///
    /// Each renderer draws one exactly as its case says, so they agree without sharing a
    /// drawing routine: fill the polygon or disc with the stroke's paint, or stroke the
    /// polyline as the connection's line is stroked — its width, cap and join, centered.
    enum Shape: Friendly {
        /// A closed polygon to fill: a ``PenNode/ConnectionData/Arrowhead/triangle``, its
        /// tip first.
        case filled([PenPoint])
        /// An open polyline to stroke: a ``PenNode/ConnectionData/Arrowhead/chevron``'s two
        /// arms, its tip in the middle.
        case stroked([PenPoint])
        /// A disc to fill: a ``PenNode/ConnectionData/Arrowhead/circle``.
        case disc(center: PenPoint, radius: Double)
    }

    /// How long a triangle or chevron is along the line, in points, for a stroke of
    /// `width`: `3 × width + 8`.
    ///
    /// - Parameter width: The stroke's width.
    /// - Returns: The length from tip to base.
    static func length(forStrokeWidth width: Double) -> Double {
        3 * width + 8
    }

    /// How far a triangle or chevron reaches either side of the line: half its length.
    ///
    /// - Parameter width: The stroke's width.
    /// - Returns: The half width of its base.
    static func halfWidth(forStrokeWidth width: Double) -> Double {
        length(forStrokeWidth: width) / 2
    }

    /// A circle's radius for a stroke of `width`: `1.5 × width + 3`.
    ///
    /// - Parameter width: The stroke's width.
    /// - Returns: The radius.
    static func radius(forStrokeWidth width: Double) -> Double {
        1.5 * width + 3
    }

    /// The arrowhead at an end of the line, and how far it cuts the line back from that end.
    ///
    /// - Parameters:
    ///   - anchor: Where the line ends: the anchor's point.
    ///   - direction: The unit direction the line runs at that end, toward the anchor.
    ///   - width: The stroke's width.
    ///   - join: The stroke's join, which sets how far a chevron's tip reaches past its point.
    /// - Returns: The shape and the cut, or `nil` for ``none``.
    internal func shape(
        at anchor: PenPoint, direction: PenPoint, width: Double, join: PenStrokeJoin?
    ) -> (shape: Shape, cut: Double)? {
        let length = Self.length(forStrokeWidth: width)
        let half = Self.halfWidth(forStrokeWidth: width)
        let across = PenPoint(x: -direction.y, y: direction.x)
        func point(_ from: PenPoint, back: Double, side: Double) -> PenPoint {
            PenPoint(
                x: from.x - direction.x * back + across.x * side,
                y: from.y - direction.y * back + across.y * side
            )
        }
        switch self {
        case .none:
            return nil
        case .triangle:
            return (.filled([anchor, point(anchor, back: length, side: half),
                             point(anchor, back: length, side: -half)]), length)
        case .circle:
            let radius = Self.radius(forStrokeWidth: width)
            return (.disc(center: point(anchor, back: radius, side: 0), radius: radius), radius)
        case .chevron:
            // The stroked tip reaches past its point by the join's reach, so set the point
            // back by that much for the painted tip to land on the anchor.
            let sine = half / (length * length + half * half).squareRoot()
            let reach: Double = switch join {
            case .miter, nil: width / 2 / sine
            case .round: width / 2
            case .bevel: width / 2 * sine
            }
            let tip = point(anchor, back: reach, side: 0)
            return (.stroked([point(tip, back: length, side: half), tip, point(tip, back: length, side: -half)]), reach)
        }
    }
}
