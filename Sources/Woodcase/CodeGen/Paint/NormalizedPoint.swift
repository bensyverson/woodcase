//
//  NormalizedPoint.swift
//  Woodcase
//

/// A point in a node's normalised box: `(0, 0)` is the top-left corner and `(1, 1)` the
/// bottom-right, whatever the box's size, with y growing downward.
///
/// Pen lays out every paint in this box and only then stretches it to the node, so a
/// paint's geometry is stated here and each emitter maps it onto its own box — CSS as
/// percentages, SwiftUI as a `UnitPoint`.
struct NormalizedPoint: Friendly {
    /// The fraction of the box's width.
    var x: Double

    /// The fraction of the box's height.
    var y: Double

    /// The middle of the box.
    static let center = NormalizedPoint(x: 0.5, y: 0.5)
}
