//
//  PenRect+Union.swift
//  Woodcase
//

import Foundation

extension PenRect {
    /// The smallest rect holding both. Neither is read as empty: a zero-size rect still
    /// holds its corner.
    func union(_ other: PenRect) -> PenRect {
        let minX = Swift.min(x, other.x), minY = Swift.min(y, other.y)
        let maxX = Swift.max(maxX, other.maxX), maxY = Swift.max(maxY, other.maxY)
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The rect grown outward by a distance on each side.
    func outset(top: Double, right: Double, bottom: Double, left: Double) -> PenRect {
        PenRect(x: x - left, y: y - top, width: width + left + right, height: height + top + bottom)
    }

    /// The rect grown outward by `distance` on every side.
    func outset(by distance: Double) -> PenRect {
        outset(top: distance, right: distance, bottom: distance, left: distance)
    }

    /// The bounds of a set of points, or `nil` when there are none.
    static func bounds(of points: [PenPoint]) -> PenRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
