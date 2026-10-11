//
//  PenLayoutEngine+NoteGrowth.swift
//  Woodcase
//

import Foundation

extension PenLayoutEngine {
    /// What a note's, prompt's or context's text measures as: its markdown's display text, runs and indents
    /// (``PenNode/noteMarkdown``) in its style (``PenNode/noteTextStyle``).
    ///
    /// - Parameter node: Any node.
    /// - Returns: The request, unwrapped, or `nil` for a node that is not a note, prompt or
    ///   context, or has no literal content.
    static func noteTextRequest(_ node: PenNode) -> PenTextMeasureRequest? {
        guard let markdown = node.noteMarkdown, let style = node.noteTextStyle else { return nil }
        let weight = style.fontWeight
        return PenTextMeasureRequest(
            text: markdown.displayText,
            fontFamily: style.fontFamily,
            fontSize: style.fontSize,
            fontWeight: weight.rounded() == weight ? String(Int(weight)) : String(weight),
            fontStyle: style.isItalic ? "italic" : nil,
            letterSpacing: style.letterSpacing,
            lineHeight: style.lineHeight,
            runs: markdown.runs,
            indents: markdown.indents
        )
    }

    /// A note's laid-out height: its set height, or its text's height at its width plus
    /// its insets — ``PenPostIt/bodyInsets(of:style:)``, its chrome included — whichever
    /// is more. Prompts and contexts grow the same way.
    ///
    /// A note grows to fit and never shrinks (Penumbra's notes design, decision 4): the
    /// height is the layout's, so `tree`, hit testing and every renderer read the grown
    /// rect, and the file keeps the height that was set. The width is never changed.
    ///
    /// - Parameters:
    ///   - text: The note's text (``noteTextRequest(_:)``).
    ///   - insets: The space around its text.
    ///   - width: The note's laid-out width.
    ///   - setHeight: The height its sizing resolved to.
    ///   - textMeasurer: The measurer the layout uses.
    /// - Returns: The height to lay the note out at.
    static func grownNoteHeight(
        _ text: PenTextMeasureRequest, insets: PenPadding.Edges, width: Double, setHeight: Double,
        textMeasurer: TextMeasurer
    ) -> Double {
        guard !text.text.isEmpty else { return setHeight }
        var request = text
        request.maxWidth = max(0, width - insets.horizontal)
        return max(setHeight, textMeasurer(request).height + insets.vertical)
    }
}
