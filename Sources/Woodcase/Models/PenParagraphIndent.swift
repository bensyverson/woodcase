//
//  PenParagraphIndent.swift
//  Woodcase
//

import Foundation

/// A paragraph's indents and the space after it: how far its first line and its wrapped
/// lines start from the left edge of the box, and how much further down the next
/// paragraph starts.
///
/// It is the one paragraph-level value the span model has. A ``PenTextRun`` styles
/// characters; a paragraph's indents and spacing cannot ride on a run, because Core Text
/// reads them once per paragraph. A note's markdown sets one per list item
/// (``PenNoteMarkdown/indents``): the marker on the first line at ``firstLineIndent``, a
/// tab, and the item's words at ``headIndent`` on every line — a hanging indent. It sets
/// one per heading too, with no indent and ``spacingAfter``, so a heading stands off the
/// text below it.
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

    /// The space between the paragraph's last line and the next line, in points; 0 for
    /// none.
    ///
    /// It is added only between lines: a block's last paragraph adds nothing below it, so a
    /// text's measured height never ends in empty space. ``PenTextLines/bands`` places the
    /// lines, so drawing, measuring and an editor's carets all see the gap.
    public var spacingAfter: Double

    /// Creates a paragraph's indents and spacing.
    ///
    /// - Parameters:
    ///   - start: The paragraph's first UTF-16 offset.
    ///   - end: The UTF-16 offset just past it.
    ///   - firstLineIndent: Where its first line starts, in points.
    ///   - headIndent: Where its later lines and its tab stop start, in points.
    ///   - spacingAfter: The space below its last line, in points.
    public init(start: Int, end: Int, firstLineIndent: Double, headIndent: Double, spacingAfter: Double = 0) {
        self.start = start
        self.end = end
        self.firstLineIndent = firstLineIndent
        self.headIndent = headIndent
        self.spacingAfter = spacingAfter
    }

    /// Whether the paragraph's lines start anywhere but the box's left edge.
    var isIndented: Bool {
        firstLineIndent != 0 || headIndent != 0
    }

    /// The UTF-16 range the indent covers; empty when `end` is not past `start`.
    public var range: Range<Int> {
        start ..< max(start, end)
    }
}
