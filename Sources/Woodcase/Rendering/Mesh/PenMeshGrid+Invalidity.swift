//
//  PenMeshGrid+Invalidity.swift
//  Woodcase
//

import Foundation

public extension PenMeshGrid {
    /// Why a mesh gradient fill is not drawn at all.
    ///
    /// Pen's exports show it painting nothing for a fill in any of these states rather
    /// than guessing at the missing data, and Woodcase does the same. The lint check
    /// reports them; the renderer skips the fill.
    enum Invalidity: Error, Friendly {
        /// The fill has no `columns`.
        case missingColumns

        /// The fill has no `rows`.
        case missingRows

        /// The fill has no `points`.
        case missingPoints

        /// The fill has no `colors`.
        case missingColors

        /// `columns` or `rows` is zero or negative.
        case nonPositiveDimension(columns: Int, rows: Int)

        /// `points` or `colors` does not hold exactly `columns × rows` entries.
        case countMismatch(expected: Int, points: Int, colors: Int)

        /// The point at `index` (row-major, from 0) is malformed in a way Pen cannot place.
        ///
        /// See ``PenMeshPoint/placement(gridPosition:defaults:)``.
        case unplaceablePoint(index: Int)
    }
}
