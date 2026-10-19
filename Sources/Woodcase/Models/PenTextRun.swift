//
//  PenTextRun.swift
//  Woodcase
//

import Foundation

/// A styled range of a text node's content: one run of rich text.
///
/// A run covers ``start`` up to ``end`` and overrides only the character style keys it sets;
/// every key left `nil` — and every range no run covers — inherits the node's own text
/// style. Paragraph keys (line height, letter spacing, alignment) are the node's alone.
///
/// ## Offsets are UTF-16 code units
///
/// ``start`` and ``end`` count UTF-16 code units, the unit Core Text, `NSString`, `NSRange`,
/// `NSTextInputClient` and ``PenTextGeometry`` all count in, so a caret index from an
/// editor is a run offset with no conversion. Not graphemes: "👍🏽" is one grapheme but four
/// code units. Not scalars or bytes either. An edge that falls inside a grapheme cluster
/// (a surrogate pair, a combining sequence, an emoji ZWJ sequence) is widened outward to
/// the whole cluster when the run is set (``PenTextStyle/segments(of:runs:)``), so a run
/// never splits a character's glyphs between two faces; an editor should still write runs
/// on caret boundaries.
///
/// ## Overlaps and bounds
///
/// Runs may overlap: where they do, a later run in the list wins for the keys it sets, so an
/// editor can bold a selection by appending a run. A run is clamped to the text, and one
/// that is empty or inverted after clamping sets nothing.
///
/// Its storage on a text node is the `woodcase.spans` metadata key, never `content`: see
/// ``PenTextSpans``.
public struct PenTextRun: Friendly {
    /// The first UTF-16 offset the run covers.
    public var start: Int

    /// The UTF-16 offset just past the run: it covers `start ..< end`.
    public var end: Int

    /// The font family, or `nil` to inherit the node's.
    public var fontFamily: String?

    /// The font size in points, or `nil` to inherit the node's.
    public var fontSize: Double?

    /// The CSS weight, 100–900, or `nil` to inherit the node's — as
    /// ``PenTextStyle/fontWeight`` holds it, so a variable face's 450 stays 450.
    public var fontWeight: Double?

    /// Whether the italic face is set, or `nil` to inherit the node's.
    public var isItalic: Bool?

    /// The glyphs' color, or `nil` to take the node's paint.
    public var fill: PenHexColor?

    /// Whether the run is underlined, or `nil` to inherit the node's.
    public var underline: Bool?

    /// Whether the run is struck through, or `nil` to inherit the node's.
    public var strikethrough: Bool?

    /// The name the run mentions — `claude` for `@claude` — or `nil` for a run that is
    /// not a mention.
    ///
    /// It is not a style: it says *who*, so a renderer can draw the run as a pill in
    /// that identity's color. Woodcase does not resolve names to colors; an identity's
    /// color is the editor's presence color. It never changes a size, so it is left out
    /// of a measurement's cache key (``PenTextMeasureRequest/ignoringColor``), and it
    /// reaches the renderer on ``PenTextSegment/mention``.
    public var mention: String?

    /// The URL the run links to, as written — `https://example.com` — or `nil` for a run
    /// that is not a link.
    ///
    /// It is not a style: a linked run is drawn as its other keys say, so a renderer adds
    /// no color or underline of its own — the app a link was pasted from gives it its
    /// color and underline as ``fill`` and ``underline``, which travel separately. It never
    /// changes a size, so it is left out of a measurement's cache key
    /// (``PenTextMeasureRequest/ignoringColor``).
    public var link: String?

    /// Horizontal padding on each side of the run, in points, or `nil` for none: CSS's
    /// `padding-inline` on an inline element.
    ///
    /// It is laid out, not drawn: the run's text starts this much after what precedes it
    /// and what follows starts this much after the run, so wrapping, measuring, carets and
    /// every renderer see it (``PenTextStyle/attributedString(_:runs:indents:for:)``). At a
    /// paragraph's start the run's text starts this far in from the text column. A note's
    /// mention takes ``PenNoteMarkdown/mentionPadding``, the room its pill is drawn in. It
    /// is not a `woodcase.spans` wire key: a text node's spans cannot set it.
    public var inlinePadding: Double?

    /// Creates a run over `start ..< end`; every style key left out inherits the node's.
    ///
    /// - Parameters:
    ///   - start: The first UTF-16 offset covered.
    ///   - end: The UTF-16 offset just past the run.
    ///   - fontFamily: The font family.
    ///   - fontSize: The font size in points.
    ///   - fontWeight: The CSS weight.
    ///   - isItalic: Whether the italic face is set.
    ///   - fill: The glyphs' color.
    ///   - underline: Whether the run is underlined.
    ///   - strikethrough: Whether the run is struck through.
    ///   - mention: The name the run mentions, or `nil`.
    ///   - link: The URL the run links to, or `nil`.
    ///   - inlinePadding: The horizontal padding on each side, in points.
    public init(
        start: Int,
        end: Int,
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        fontWeight: Double? = nil,
        isItalic: Bool? = nil,
        fill: PenHexColor? = nil,
        underline: Bool? = nil,
        strikethrough: Bool? = nil,
        mention: String? = nil,
        link: String? = nil,
        inlinePadding: Double? = nil
    ) {
        self.start = start
        self.end = end
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.isItalic = isItalic
        self.fill = fill
        self.underline = underline
        self.strikethrough = strikethrough
        self.mention = mention
        self.link = link
        self.inlinePadding = inlinePadding
    }

    /// The UTF-16 range the run covers, as written; empty when `end` is not past `start`.
    public var range: Range<Int> {
        start ..< max(start, end)
    }
}
