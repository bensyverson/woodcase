//
//  PenPostIt+BodyText.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// How a note's, prompt's or context's body is drawn: styled from its markdown, or
    /// raw, as written.
    ///
    /// A card shows its markdown styled at rest and raw while it is edited (Penumbra's
    /// notes design, decision 6), so an editor's draft — the content as written, in
    /// ``PenNode/noteTextStyle``, in ``textFrame(of:width:height:style:)`` — lies over the
    /// drawn body line for line. Only the body changes: the paper, the labels, the author
    /// line, the Run button and the box are the same either way, so a card does not move
    /// when editing begins.
    enum BodyText: String, Friendly, CaseIterable {
        /// The markdown's display text, runs and paragraph indents, with its mention pills,
        /// bullets, checkboxes and check marks drawn behind it.
        case styled
        /// The content exactly as written, in the note's text style alone: no runs, no
        /// indents and no marks. Its mentions are not pills, so the expansion lists none,
        /// and its checklist has no boxes to hit.
        case raw
    }
}
