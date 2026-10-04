//
//  PenNode+NoteData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Note

    /// A note: a sticky note on the canvas, with a size and the TextStyle keys.
    ///
    /// Pen declares `Note extends Entity, Size, TextStyle` and gives it no fill, so a
    /// note carries ``width``, ``height`` and the eleven ``PenTextStyleProperties`` keys and
    /// nothing paintable. A note whose width or height is absent or not above zero —
    /// Pen saves an unsized note as `width: 0, height: 0` — lays out at
    /// ``PenPostIt/defaultSize`` on that axis. Its tint and author live in its metadata;
    /// see <doc:PenPostItConvention>.
    struct NoteData: Friendly, PenTextStyleProperties {
        /// Creates a note payload.
        ///
        /// - Parameters:
        ///   - width: The note's width; absent or ≤ 0 lays out at ``PenPostIt/defaultSize``.
        ///   - height: The note's height; absent or ≤ 0 lays out at ``PenPostIt/defaultSize``.
        ///   - content: The note's text.
        ///   - fontFamily: The font family.
        ///   - fontSize: The font size in points.
        ///   - fontWeight: The font weight.
        ///   - fontStyle: The font style.
        ///   - letterSpacing: Extra space between glyphs, in points.
        ///   - lineHeight: The line height as a multiple of the font size.
        ///   - textAlign: The horizontal alignment.
        ///   - textAlignVertical: The vertical alignment.
        ///   - underline: Whether the text is underlined.
        ///   - strikethrough: Whether the text is struck through.
        ///   - href: A link the text opens.
        public init(
            width: PenSizing? = nil,
            height: PenSizing? = nil,
            content: PenValue<String>? = nil,
            fontFamily: PenValue<String>? = nil,
            fontSize: PenValue<Double>? = nil,
            fontWeight: PenValue<String>? = nil,
            fontStyle: PenValue<String>? = nil,
            letterSpacing: PenValue<Double>? = nil,
            lineHeight: PenValue<Double>? = nil,
            textAlign: PenTextAlign? = nil,
            textAlignVertical: PenTextAlignVertical? = nil,
            underline: PenValue<Bool>? = nil,
            strikethrough: PenValue<Bool>? = nil,
            href: String? = nil
        ) {
            self.width = width
            self.height = height
            self.content = content
            self.fontFamily = fontFamily
            self.fontSize = fontSize
            self.fontWeight = fontWeight
            self.fontStyle = fontStyle
            self.letterSpacing = letterSpacing
            self.lineHeight = lineHeight
            self.textAlign = textAlign
            self.textAlignVertical = textAlignVertical
            self.underline = underline
            self.strikethrough = strikethrough
            self.href = href
        }

        /// The note's width; absent or ≤ 0 lays out at ``PenPostIt/defaultSize``.
        public var width: PenSizing?
        /// The note's height; absent or ≤ 0 lays out at ``PenPostIt/defaultSize``.
        public var height: PenSizing?
        /// The note's text.
        public var content: PenValue<String>?
        /// The font family name, or a `$variable` naming one.
        public var fontFamily: PenValue<String>?
        /// The font size in points.
        public var fontSize: PenValue<Double>?
        /// The font weight, as Pen spells it.
        public var fontWeight: PenValue<String>?
        /// The font style: `"normal"` or `"italic"`.
        public var fontStyle: PenValue<String>?
        /// Extra space between glyphs, in points.
        public var letterSpacing: PenValue<Double>?
        /// The line height as a multiple of the font size, not points.
        public var lineHeight: PenValue<Double>?
        /// The horizontal alignment of each line.
        public var textAlign: PenTextAlign?
        /// The vertical alignment of the text in the note.
        public var textAlignVertical: PenTextAlignVertical?
        /// Whether the text is underlined.
        public var underline: PenValue<Bool>?
        /// Whether the text is struck through.
        public var strikethrough: PenValue<Bool>?
        /// A link the text opens.
        public var href: String?
    }
}
