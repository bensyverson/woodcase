//
//  PenTextStyleProperties.swift
//  Woodcase
//

import Foundation

/// A node payload that carries Pen's `TextStyle` keys.
///
/// The .pen schema gives `text`, `note`, `prompt` and `context` the same eleven
/// TextStyle keys (`Text|Note|Prompt|Context extends … TextStyle`), so every one of
/// those payloads declares them under the same names and Swift types. This protocol is
/// how the variable resolver, the property diff and ``PenTextStyle/init(_:)`` address
/// them once rather than four times.
///
/// These are the keys as the file writes them, each optional and possibly a
/// `$variable`. ``PenTextStyle`` is the resolved form, with every default applied — the
/// same defaults for all four node types.
public protocol PenTextStyleProperties {
    /// The font family name, or a `$variable` naming one.
    var fontFamily: PenValue<String>? { get set }
    /// The font size in points.
    var fontSize: PenValue<Double>? { get set }
    /// The weight, as Pen spells it (`"400"`, `"700"`, `"bold"`).
    var fontWeight: PenValue<String>? { get set }
    /// The style: `"normal"` or `"italic"`.
    var fontStyle: PenValue<String>? { get set }
    /// Extra space between glyphs, in points.
    var letterSpacing: PenValue<Double>? { get set }
    /// The line height as a multiple of ``fontSize``, not points.
    var lineHeight: PenValue<Double>? { get set }
    /// The horizontal alignment of each line.
    var textAlign: PenTextAlign? { get set }
    /// The vertical alignment of the text in its box.
    var textAlignVertical: PenTextAlignVertical? { get set }
    /// Whether the text is underlined.
    var underline: PenValue<Bool>? { get set }
    /// Whether the text is struck through.
    var strikethrough: PenValue<Bool>? { get set }
    /// A link the text opens.
    var href: String? { get set }
}
