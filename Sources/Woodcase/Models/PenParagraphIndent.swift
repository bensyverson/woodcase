//
//  PenParagraphIndent.swift
//  Woodcase
//

import Foundation

/// A paragraph's indents: how far its first line and its wrapped lines start from the
/// left edge of the box.
///
/// It is the one paragraph-level key the span model has. A ``PenTextRun`` styles
/// characters; a paragraph's indents cannot ride on a run, because Core Text reads them
/// once per paragraph. A note's markdown sets one per list item
/// (``PenNoteMarkdown/indents``): the marker on the first line at ``firstLineIndent``, a
/// tab, and the item's words at ``headIndent`` on every line — a hanging indent.
///
/// The paragraph also takes a tab stop at ``headIndent``, so a marker followed by a tab
/// starts its words exactly where the wrapped lines start. A marker wider than the gap
/// pushes the tab to the next default stop, as in any text editor.
///
/// Offsets are UTF-16 code units, as a run's are. An indent applies to every paragraph
/// it touches; it should cover one paragraph, from its first character through its
/// newline.
public struct PenParagraphIndent: Friendly {
    /// The first UTF-16 offset of the paragraph.
    public var start: Int

    /// The UTF-16 offset just past the paragraph, its newline included.
    public var end: Int

    /// How far the paragraph's first line starts from the box's left edge, in points.
    public var firstLineIndent: Double

    /// How far each later line of the paragraph starts, and where its tab stop sits, in
    /// points.
    public var headIndent: Double

    /// Creates a paragraph's indents.
    ///
    /// - Parameters:
    ///   - start: The paragraph's first UTF-16 offset.
    ///   - end: The UTF-16 offset just past it.
    ///   - firstLineIndent: Where its first line starts, in points.
    ///   - headIndent: Where its later lines and its tab stop start, in points.
    public init(start: Int, end: Int, firstLineIndent: Double, headIndent: Double) {
        self.start = start
        self.end = end
        self.firstLineIndent = firstLineIndent
        self.headIndent = headIndent
    }

    /// The UTF-16 range the indent covers; empty when `end` is not past `start`.
    public var range: Range<Int> {
        start ..< max(start, end)
    }
}
