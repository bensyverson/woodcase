//
//  PenPostIt+Text.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// The space between a note's edges and its text, in points: 14 on every side, as
    /// the rev 2 mockup pads a post-it.
    ///
    /// The layout grows a note by its text's height plus this padding, and a renderer
    /// sets the text in the box these insets leave (``textFrame(inNoteOfWidth:height:)``),
    /// so the two agree on where the text ends.
    static let textInsets = PenPadding.Edges(top: 14, right: 14, bottom: 14, left: 14)

    /// Where a note's text is set: its box less ``textInsets``, in the note's own
    /// coordinates.
    ///
    /// - Parameters:
    ///   - width: The note's laid-out width.
    ///   - height: The note's laid-out height.
    /// - Returns: The text's frame; never narrower or shorter than zero.
    static func textFrame(inNoteOfWidth width: Double, height: Double) -> PenRect {
        PenRect(
            x: textInsets.left,
            y: textInsets.top,
            width: max(0, width - textInsets.horizontal),
            height: max(0, height - textInsets.vertical)
        )
    }
}
