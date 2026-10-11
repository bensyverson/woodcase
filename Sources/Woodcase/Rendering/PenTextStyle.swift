//
//  PenTextStyle.swift
//  Woodcase
//

import Foundation

/// How a text is set: its face, size, spacing, alignment and decorations, with every
/// default applied.
///
/// A text node's style properties are each optional in the format; this is the one place
/// their defaults are decided — SF Pro 16, regular, upright, natural line height, top-left,
/// undecorated — so every consumer that sets text (the CG renderer, layout measurement,
/// RapidPro's rasterizer, an editor's caret geometry) sets it the same way. It is plain
/// data: on Apple platforms ``attributedString(_:runs:for:)`` turns it and a string into the
/// Core Text string all of them typeset. Being ``Friendly``, it also serves as a cache
/// key for rasterized text.
public struct PenTextStyle: Friendly {
    /// The family set when a text names none: SF Pro.
    public static let defaultFontFamily = "SF Pro"

    /// The size, in points, set when a text names none: 16.
    public static let defaultFontSize: Double = 16

    /// The CSS weight set when a text names none: 400, regular.
    public static let defaultFontWeight: Double = 400

    /// The font family name.
    public var fontFamily: String

    /// The font size in points.
    public var fontSize: Double

    /// The CSS weight, 100–900 — any number, so a variable face's 450 stays 450.
    public var fontWeight: Double

    /// Whether the italic face is set.
    public var isItalic: Bool

    /// Extra space between characters in points, or `nil` for the font's own kerning.
    ///
    /// Kept optional on purpose: Core Text reads an explicit 0 as "no kerning at all",
    /// which differs from leaving the attribute out.
    public var letterSpacing: Double?

    /// The line height as a multiple of the font size, or `nil` for the font's natural
    /// line height (see `PenTextMeasurer.linePitch(lineHeight:fontSize:font:)`).
    public var lineHeight: Double?

    /// The horizontal alignment.
    public var textAlign: PenTextAlign

    /// The vertical alignment of the block of lines in its box.
    public var textAlignVertical: PenTextAlignVertical

    /// Whether the text is underlined.
    public var underline: Bool

    /// Whether the text is struck through.
    public var strikethrough: Bool

    /// Creates a style; every property left out takes its default.
    ///
    /// - Parameters:
    ///   - fontFamily: The font family name.
    ///   - fontSize: The font size in points.
    ///   - fontWeight: The CSS weight.
    ///   - isItalic: Whether the italic face is set.
    ///   - letterSpacing: Extra space between characters in points, or `nil` for none.
    ///   - lineHeight: The line height as a multiple of the font size, or `nil` for natural.
    ///   - textAlign: The horizontal alignment.
    ///   - textAlignVertical: The vertical alignment.
    ///   - underline: Whether the text is underlined.
    ///   - strikethrough: Whether the text is struck through.
    public init(
        fontFamily: String = defaultFontFamily,
        fontSize: Double = defaultFontSize,
        fontWeight: Double = defaultFontWeight,
        isItalic: Bool = false,
        letterSpacing: Double? = nil,
        lineHeight: Double? = nil,
        textAlign: PenTextAlign = .left,
        textAlignVertical: PenTextAlignVertical = .top,
        underline: Bool = false,
        strikethrough: Bool = false
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.isItalic = isItalic
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.textAlign = textAlign
        self.textAlignVertical = textAlignVertical
        self.underline = underline
        self.strikethrough = strikethrough
    }

    /// The style a node carrying the format's TextStyle keys sets its content in.
    ///
    /// A `text`, `note`, `prompt` or `context` all carry the same keys
    /// (``PenTextStyleProperties``), so all four resolve through the same defaults here.
    /// Only literal values count: a property still holding an unresolved `$variable`
    /// takes its default, as the renderer has always drawn it.
    ///
    /// - Parameter data: The node's data.
    public init(_ data: some PenTextStyleProperties) {
        self.init(
            fontFamily: data.fontFamily?.literalValue ?? Self.defaultFontFamily,
            fontSize: data.fontSize?.literalValue ?? Self.defaultFontSize,
            fontWeight: Self.weight(data.fontWeight?.literalValue),
            isItalic: Self.isItalic(data.fontStyle?.literalValue),
            letterSpacing: data.letterSpacing?.literalValue,
            lineHeight: data.lineHeight?.literalValue,
            textAlign: data.textAlign ?? .left,
            textAlignVertical: data.textAlignVertical ?? .top,
            underline: data.underline?.literalValue ?? false,
            strikethrough: data.strikethrough?.literalValue ?? false
        )
    }

    /// The CSS weight a `fontWeight` string names, or the default for none.
    ///
    /// - Parameter fontWeight: A keyword or a number, as the format writes it.
    /// - Returns: The CSS weight (``PenFontWeight/cssWeight(_:)``).
    static func weight(_ fontWeight: String?) -> Double {
        fontWeight.map(PenFontWeight.cssWeight) ?? defaultFontWeight
    }

    /// Whether a `fontStyle` string selects the italic face: `"italic"`, in any case.
    ///
    /// - Parameter fontStyle: The format's `fontStyle`, if set.
    /// - Returns: `true` for italic.
    static func isItalic(_ fontStyle: String?) -> Bool {
        fontStyle?.lowercased() == "italic"
    }
}
