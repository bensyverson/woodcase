//
//  PenPostIt+Body.swift
//  Woodcase
//

import Foundation

extension PenPostIt {
    /// A note's, prompt's or context's body: its markdown's display text, runs and indents
    /// in its own style, set in ``textFrame(of:width:height:style:)``, and its mentions.
    ///
    /// Two marks are quieter than the text, in the tertiary ink: a list's bullets, and a
    /// ticked checklist item's words. Both are runs carrying only a fill, so they change
    /// no line break: the layout an editor builds from ``PenTextLayout/init(note:size:color:)``
    /// still lies over the body exactly.
    ///
    /// - Parameters:
    ///   - node: The node.
    ///   - box: Its laid-out size.
    ///   - color: The body's ink.
    ///   - ink: The inks, for the quieter marks.
    ///   - style: The look.
    /// - Returns: The part, or `nil` when the node has no text to set, and the mentions.
    static func bodyPart(
        of node: PenNode, box: (width: Double, height: Double), color: PenHexColor, ink: Ink, style: Style
    ) -> (part: PenPostItExpansion.Part?, mentions: [PenPostItExpansion.Mention]) {
        guard let markdown = node.noteMarkdown, let textStyle = node.noteTextStyle, !markdown.displayText.isEmpty
        else { return (nil, []) }
        let mentions = markdown.runs.compactMap { run in
            run.mention.map { PenPostItExpansion.Mention(range: run.range, name: $0) }
        }
        let text = PenPostItExpansion.Text(
            string: markdown.displayText, style: textStyle,
            runs: markdown.runs + quietRuns(of: markdown, ink: ink), indents: markdown.indents, color: color
        )
        let part = PenPostItExpansion.Part(
            role: .body, frame: textFrame(of: node, width: box.width, height: box.height, style: style), paint: .text(text)
        )
        return (part, mentions)
    }

    /// Fill-only runs that draw a list's bullets and a ticked item's words in the
    /// tertiary ink.
    private static func quietRuns(of markdown: PenNoteMarkdown, ink: Ink) -> [PenTextRun] {
        let units = Array(markdown.displayText.utf16)
        let bullet = PenNoteMarkdown.bulletGlyph.utf16.first
        let bullets = markdown.indents.compactMap { indent -> PenTextRun? in
            guard units.indices.contains(indent.start), units[indent.start] == bullet else { return nil }
            return PenTextRun(start: indent.start, end: indent.start + 1, fill: ink.tertiary)
        }
        let ticked = markdown.checklistItems.filter(\.isChecked).map { item in
            PenTextRun(start: item.boxDisplayRange.upperBound, end: item.lineDisplayRange.upperBound, fill: ink.tertiary)
        }
        return bullets + ticked
    }
}
