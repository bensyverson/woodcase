//
//  PenTextLayout+Note.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreGraphics
    import Foundation

    public extension PenTextLayout {
        /// Sets a note's, prompt's or context's markdown — its display text, runs and list
        /// indents (``PenNode/noteMarkdown``) — in its style (``PenNode/noteTextStyle``), in
        /// the box its ``PenPostIt/bodyInsets(of:style:)`` leave.
        ///
        /// The layout's coordinates are the text frame's
        /// (``PenPostIt/textFrame(of:width:height:style:)``): offset them by that frame's
        /// origin to draw in the note's own space. It lies exactly over the expansion's
        /// ``PenPostItExpansion/Role/body`` part, so a caret placed with it sits on the
        /// line that was drawn.
        ///
        /// - Parameters:
        ///   - note: The note (or comment).
        ///   - size: The note's laid-out size, grown to fit its text.
        ///   - color: The glyphs' color.
        /// - Returns: The layout, or `nil` when the node is not a note or has no literal
        ///   content.
        init?(note: PenNode, size: CGSize, color: CGColor = defaultColor) {
            guard let markdown = note.noteMarkdown, let style = note.noteTextStyle else { return nil }
            let frame = PenPostIt.textFrame(of: note, width: Double(size.width), height: Double(size.height))
            self.init(
                text: markdown.displayText, style: style, runs: markdown.runs, indents: markdown.indents,
                box: CGSize(width: frame.width, height: frame.height), color: color
            )
        }
    }
#endif
