//
//  PenNode+NoteScale.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// What a note's look scale (``PenMetadata/WoodcaseKey/scale``) must be when it is
    /// written: a factor above 0.
    static let scaleConstraint = PenValueConstraint(unit: .factor, minimum: .exclusive(0))
}

public extension PenNode {
    /// The factor a note's, prompt's or context's look is drawn at: its
    /// `metadata.woodcase.scale` (`note.scale`), or 1 where it has none, or one that is not
    /// a finite number above 0.
    ///
    /// The look — corner radius, padding, hairline, shadows, the author line and a card's
    /// chrome — multiplies by it, independent of the type size, so notes of one size may
    /// set different type sizes and changing the type size alone leaves the look alone
    /// (Ben's ruling of 2026-10-20). A proportional scale multiplies it with the box and
    /// the type (``ScaleCapture``). See <doc:PenPostItLook>.
    ///
    /// ```swift
    /// note.noteScale  // 2 for {"woodcase": {"scale": 2}}; 1 for none
    /// ```
    ///
    /// `nil` for a node that is not a note, prompt or context.
    var noteScale: Double? {
        guard PenPostIt.Variant(kind) != nil else { return nil }
        return noteTextStyleReading?.number(.scale) ?? 1
    }
}
