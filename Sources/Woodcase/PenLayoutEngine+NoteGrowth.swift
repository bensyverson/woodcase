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
        guard let markdown = node.noteMarkdown, var request = noteRawTextRequest(node) else { return nil }
        request.text = markdown.displayText
        request.runs = markdown.runs
        request.indents = markdown.indents
        return request
    }

    /// What a note's, prompt's or context's raw text measures as: its markdown source
    /// verbatim in its style (``PenNode/noteTextStyle``), with no runs and no indents —
    /// the body an editor draws while the card is edited (``PenPostIt/BodyText/raw``).
    ///
    /// - Parameter node: Any node.
    /// - Returns: The request, unwrapped, or `nil` for a node that is not a note, prompt or
    ///   context, or has no literal content.
    static func noteRawTextRequest(_ node: PenNode) -> PenTextMeasureRequest? {
        guard let source = node.noteSource, let style = node.noteTextStyle else { return nil }
        let weight = style.fontWeight
        return PenTextMeasureRequest(
            text: source,
            fontFamily: style.fontFamily,
            fontSize: style.fontSize,
            fontWeight: weight.rounded() == weight ? String(Int(weight)) : String(weight),
            fontStyle: style.isItalic ? "italic" : nil,
            letterSpacing: style.letterSpacing,
            lineHeight: style.lineHeight
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
