//
//  PenNode+PromptData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Prompt

    /// A prompt: an instruction for a model, placed on the canvas.
    ///
    /// Pen declares `Prompt extends Entity, Size, TextStyle` plus a `model`, so it
    /// carries ``width``, ``height``, ``model`` and the eleven ``PenTextStyleProperties`` keys.
    /// Unlike a note it is not drawn, and an unsized one keeps a 0×0 rect.
    struct PromptData: Friendly, PenTextStyleProperties {
        /// Creates a prompt payload.
        ///
        /// - Parameters:
        ///   - width: The node's width; absent lays out at 0.
        ///   - height: The node's height; absent lays out at 0.
        ///   - content: The prompt's text.
        ///   - model: The model the prompt is for.
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
            model: String? = nil,
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
            self.model = model
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

        /// The node's width; absent lays out at 0.
        public var width: PenSizing?
        /// The node's height; absent lays out at 0.
        public var height: PenSizing?
        /// The prompt's text.
        public var content: PenValue<String>?
        /// The model the prompt is for.
        public var model: String?
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
        /// The vertical alignment of the text in the box.
        public var textAlignVertical: PenTextAlignVertical?
        /// Whether the text is underlined.
        public var underline: PenValue<Bool>?
        /// Whether the text is struck through.
        public var strikethrough: PenValue<Bool>?
        /// A link the text opens.
        public var href: String?
    }
}
