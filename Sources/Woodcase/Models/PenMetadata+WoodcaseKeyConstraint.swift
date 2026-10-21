//
//  PenMetadata+WoodcaseKeyConstraint.swift
//  Woodcase
//

import Foundation

public extension PenMetadata.WoodcaseKey {
    /// The range, step and unit a number written to this key must keep to, or `nil` for
    /// a key that holds no number.
    ///
    /// A note's text-style numbers stand in for the `kind.` keys Pen strips from a note,
    /// so each carries exactly that key's constraint, read from the shape table rather
    /// than copied: `fontSize` above 0 in points, `lineHeight` a multiple of the font size
    /// above 0 and at most 10, `letterSpacing` any number of points. ``EditPlanner``
    /// refuses a write outside it with ``EditRefusal/Code/outOfRange``, as it does on a
    /// text. A stroke's miter limit is a factor of at least 1: a shorter miter than the
    /// stroke's own width is no miter at all. A note's look scale is a factor above 0.
    var constraint: PenValueConstraint? {
        switch self {
        case .fontSize, .lineHeight, .letterSpacing: NodePropertyCodec.shape(of: rawValue)?.constraint
        case .strokeMiterLimit: PenNode.miterLimitConstraint
        case .scale: PenPostIt.scaleConstraint
        default: nil
        }
    }
}
