//
//  PenTextLayout+Note.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreGraphics
    import Foundation

    public extension PenTextLayout {
        /// Sets a note's markdown — its display text, runs and list indents
        /// (``PenNode/noteMarkdown``) — in its style (``PenNode/noteTextStyle``), in the
        /// box its ``PenPostIt/textInsets`` leave.
        ///
        /// The layout's coordinates are the text frame's
        /// (``PenPostIt/textFrame(inNoteOfWidth:height:)``): offset them by
        /// ``PenPostIt/textInsets`` to draw in the note's own space.
        ///
        /// - Parameters:
        ///   - note: The note (or comment).
        ///   - size: The note's laid-out size, grown to fit its text.
        ///   - color: The glyphs' color.
        /// - Returns: The layout, or `nil` when the node is not a note or has no literal
        ///   content.
        init?(note: PenNode, size: CGSize, color: CGColor = defaultColor) {
            guard let markdown = note.noteMarkdown, let style = note.noteTextStyle else { return nil }
            let frame = PenPostIt.textFrame(inNoteOfWidth: Double(size.width), height: Double(size.height))
            self.init(
                text: markdown.displayText, style: style, runs: markdown.runs, indents: markdown.indents,
                box: CGSize(width: frame.width, height: frame.height), color: color
            )
        }
    }
#endif
