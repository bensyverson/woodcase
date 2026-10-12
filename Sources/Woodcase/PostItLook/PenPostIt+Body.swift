//
//  PenPostIt+Body.swift
//  Woodcase
//

import Foundation

extension PenPostIt {
    /// What a body draws: its text, the marks behind it, and the facts an editor reads.
    struct Body {
        /// The mention pills, bullets, checkboxes and check marks, drawn before the text.
        var marks: [PenPostItExpansion.Part] = []
        /// The text, or `nil` when the node has none to set.
        var text: PenPostItExpansion.Part?
        /// The mentions, with their colors.
        var mentions: [PenPostItExpansion.Mention] = []
        /// The checklist boxes, with their hit rects.
        var checkboxes: [PenPostItExpansion.Checkbox] = []

        /// The marks, then the text: the body's parts in paint order.
        var parts: [PenPostItExpansion.Part] {
            marks + (text.map { [$0] } ?? [])
        }
    }

    /// A note's, prompt's or context's body: its markdown's display text, runs and indents
    /// in its own style, set in ``textFrame(of:width:height:style:)``, and the marks drawn
    /// as shapes behind it (``bodyMarks(of:text:frame:mentions:ink:paper:chrome:)``).
    ///
    /// Two kinds of run only color the text, so they change no line break and the layout
    /// an editor builds from ``PenTextLayout/init(note:size:color:)`` still lies over the
    /// body exactly: a ticked checklist item's words in the tertiary ink, and each mention
    /// in the ink its pill's color takes (``ActorColor/Ink``).
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - box: Its laid-out size.
    ///   - color: The body's ink.
    ///   - ink: The inks, for the marks.
    ///   - paper: The paper, which a check mark is cut in.
    ///   - drawing: The look and the caller's identity colors.
    /// - Returns: The body; empty when the node has no text to set.
    static func body(
        of node: PenNode, box: (width: Double, height: Double), color: PenHexColor, ink: Ink, paper: PenHexColor,
        drawing: Drawing
    ) -> Body {
        guard let markdown = node.noteMarkdown, let textStyle = node.noteTextStyle, !markdown.displayText.isEmpty
        else { return Body() }
        let mentions = markdown.runs.compactMap { run in
            run.mention.map {
                PenPostItExpansion.Mention(range: run.range, name: $0, color: drawing.identityColor(for: $0))
            }
        }
        let mentionInk = mentions.map {
            PenTextRun(start: $0.range.lowerBound, end: $0.range.upperBound, fill: ActorColor.Ink(on: $0.color).color)
        }
        let text = PenPostItExpansion.Text(
            string: markdown.displayText, style: textStyle,
            runs: markdown.runs + tickedRuns(of: markdown, ink: ink) + mentionInk, indents: markdown.indents, color: color
        )
        let frame = textFrame(of: node, width: box.width, height: box.height, style: drawing.style)
        let marks = bodyMarks(
            of: markdown, text: text, frame: frame, mentions: mentions, ink: ink, paper: paper, chrome: drawing.chrome
        )
        return Body(
            marks: marks.parts, text: PenPostItExpansion.Part(role: .body, frame: frame, paint: .text(text)),
            mentions: mentions, checkboxes: marks.checkboxes
        )
    }

    /// Fill-only runs that draw a ticked item's words in the tertiary ink.
    private static func tickedRuns(of markdown: PenNoteMarkdown, ink: Ink) -> [PenTextRun] {
        markdown.checklistItems.filter(\.isChecked).map { item in
            PenTextRun(start: item.boxDisplayRange.upperBound, end: item.lineDisplayRange.upperBound, fill: ink.tertiary)
        }
    }
}
