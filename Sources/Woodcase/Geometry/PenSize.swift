//
//  PenSize.swift
//  Woodcase
//

import Foundation

/// A width and a height, in points.
///
/// The geometry layer's own size type, Foundation-only like ``PenPoint``. The layout
/// carries a turned node's unturned size in one (``PenRect/unturnedSize``).
public struct PenSize: Friendly {
    /// The horizontal extent.
    public var width: Double
    /// The vertical extent.
    public var height: Double

    /// Creates a size from its two extents.
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// The empty size, `0 × 0`.
    public static let zero = PenSize(width: 0, height: 0)
}
