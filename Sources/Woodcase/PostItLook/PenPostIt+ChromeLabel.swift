//
//  PenPostIt+ChromeLabel.swift
//  Woodcase
//

import Foundation

extension PenPostIt.Chrome {
    /// A one-line label part: measured, cut with an ellipsis when it is wider than
    /// `maxWidth`, and placed with its top-left at `origin`.
    ///
    /// The width is measured here, once, with the layout's text measurer, so every
    /// renderer is handed a frame and never measures chrome itself.
    ///
    /// - Parameters:
    ///   - role: What the label is.
    ///   - string: Its text.
    ///   - style: The style it is set in (``label(size:weight:tracking:)``).
    ///   - origin: Its top-left, in the node's coordinates.
    ///   - maxWidth: The most it may take; a wider label is cut.
    ///   - color: Its color.
    ///   - label: The chrome label `string` spells, if it is one.
    ///   - measure: The text measurer.
    /// - Returns: The part, as wide as its (cut) text and one line tall.
    func labelPart(
        _ role: PenPostItExpansion.Role,
        _ string: String,
        style: PenTextStyle,
        at origin: (x: Double, y: Double),
        maxWidth: Double,
        color: PenHexColor,
        label: PenPostIt.Label? = nil,
        measure: TextMeasurer
    ) -> PenPostItExpansion.Part {
        let (text, width) = fitted(string, style: style, maxWidth: maxWidth, measure: measure)
        return PenPostItExpansion.Part(
            role: role,
            frame: PenRect(x: origin.x, y: origin.y, width: width, height: lineHeight(of: style)),
            paint: .text(PenPostItExpansion.Text(string: text, style: style, color: color, label: label))
        )
    }

    /// The width a one-line label takes, rounded up to a whole point.
    ///
    /// - Parameters:
    ///   - string: The label.
    ///   - style: Its style.
    ///   - measure: The text measurer.
    /// - Returns: Its width.
    func width(of string: String, style: PenTextStyle, measure: TextMeasurer) -> Double {
        guard !string.isEmpty else { return 0 }
        let weight = style.fontWeight
        let request = PenTextMeasureRequest(
            text: string,
            fontFamily: style.fontFamily,
            fontSize: style.fontSize,
            fontWeight: weight.rounded() == weight ? String(Int(weight)) : String(weight),
            fontStyle: style.isItalic ? "italic" : nil,
            letterSpacing: style.letterSpacing,
            lineHeight: style.lineHeight
        )
        return ceil(measure(request).width)
    }

    /// One line's height in a label style.
    ///
    /// - Parameter style: The style.
    /// - Returns: Its size times its line height.
    func lineHeight(of style: PenTextStyle) -> Double {
        style.fontSize * (style.lineHeight ?? self.style.labelLineHeight)
    }

    /// A label cut, grapheme by grapheme, with a trailing ellipsis until it fits.
    ///
    /// - Parameters:
    ///   - string: The label.
    ///   - style: Its style.
    ///   - maxWidth: The width it must fit.
    ///   - measure: The text measurer.
    /// - Returns: The label as drawn and its width; an ellipsis alone when nothing fits.
    func fitted(
        _ string: String, style: PenTextStyle, maxWidth: Double, measure: TextMeasurer
    ) -> (text: String, width: Double) {
        let full = width(of: string, style: style, measure: measure)
        guard full > maxWidth else { return (string, full) }
        var kept = Array(string)
        while !kept.isEmpty {
            kept.removeLast()
            let candidate = String(kept).trimmingCharacters(in: .whitespaces) + "…"
            let width = width(of: candidate, style: style, measure: measure)
            if width <= maxWidth { return (candidate, width) }
        }
        return ("…", width(of: "…", style: style, measure: measure))
    }
}
