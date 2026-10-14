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
    /// text.
    var constraint: PenValueConstraint? {
        switch self {
        case .fontSize, .lineHeight, .letterSpacing: NodePropertyCodec.shape(of: rawValue)?.constraint
        default: nil
        }
    }
}
