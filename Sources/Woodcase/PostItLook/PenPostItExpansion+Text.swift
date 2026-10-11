//
//  PenPostItExpansion+Text.swift
//  Woodcase
//

import Foundation

public extension PenPostItExpansion {
    /// A text part: a string set in a style, with its runs and paragraph indents, in one
    /// color, top-aligned in the part's frame.
    ///
    /// A renderer sets it with ``PenTextLayout`` — `PenTextLayout(text: string, style:
    /// style, runs: runs, indents: indents, box: frame's size, color: color)` — so it
    /// breaks lines where every other renderer and an editor's caret do. The body's frame
    /// is ``PenPostIt/textFrame(of:width:height:)``, so a layout from
    /// ``PenTextLayout/init(note:size:color:)`` lies exactly over it.
    struct Text: Friendly {
        /// The string, as displayed: a body's markdown display text, or a label.
        public var string: String
        /// Its style.
        public var style: PenTextStyle
        /// Its styled runs, offsets in UTF-16 code units; a run's fill overrides ``color``.
        public var runs: [PenTextRun]
        /// Its paragraph indents: a list item's hanging indent.
        public var indents: [PenParagraphIndent]
        /// The glyphs' color where no run sets one.
        public var color: PenHexColor

        /// Creates a text part's paint.
        ///
        /// - Parameters:
        ///   - string: The string as displayed.
        ///   - style: Its style.
        ///   - runs: Its styled runs.
        ///   - indents: Its paragraph indents.
        ///   - color: The glyphs' color.
        public init(
            string: String, style: PenTextStyle, runs: [PenTextRun] = [], indents: [PenParagraphIndent] = [],
            color: PenHexColor
        ) {
            self.string = string
            self.style = style
            self.runs = runs
            self.indents = indents
            self.color = color
        }
    }
}
