//
//  PenBrowserPlaceholder+Style.swift
//  Woodcase
//

import Foundation

public extension PenBrowserPlaceholder {
    /// How the placeholder for a `browser` node looks: the one definition every
    /// Woodcase-based renderer reads, so their placeholders cannot drift apart.
    ///
    /// ``standard`` is what ``PenRenderer`` draws. A renderer that draws a browser
    /// itself (a GPU renderer, say) takes its colors, sizes and fallback label from
    /// here rather than keeping a copy.
    struct Style: Friendly {
        /// Creates a style.
        ///
        /// - Parameters:
        ///   - fillHex: The placeholder's fill, as a .pen hex color.
        ///   - borderHex: The border drawn when the node declares no stroke, as a hex color.
        ///   - borderWidth: That border's width, in points.
        ///   - borderAlignment: Where that border sits relative to the node's edge.
        ///   - labelHex: The label's color, as a hex color.
        ///   - labelSize: The label's font size, in points.
        ///   - labelInset: The space kept clear between the label and each side, in points.
        ///   - emptyLabel: What the label says when the node has no URL.
        public init(
            fillHex: String,
            borderHex: String,
            borderWidth: Double,
            borderAlignment: PenStrokeAlign,
            labelHex: String,
            labelSize: Double,
            labelInset: Double,
            emptyLabel: String
        ) {
            self.fillHex = fillHex
            self.borderHex = borderHex
            self.borderWidth = borderWidth
            self.borderAlignment = borderAlignment
            self.labelHex = labelHex
            self.labelSize = labelSize
            self.labelInset = labelInset
            self.emptyLabel = emptyLabel
        }

        /// The placeholder's fill, as a .pen hex color. A browser takes no fill of its
        /// own in the format, so this is always drawn.
        public var fillHex: String

        /// The border drawn when the node declares no stroke, as a .pen hex color. A
        /// declared stroke replaces it entirely.
        public var borderHex: String

        /// The default border's width, in points.
        public var borderWidth: Double

        /// Where the default border sits relative to the node's edge.
        public var borderAlignment: PenStrokeAlign

        /// The label's color, as a .pen hex color.
        public var labelHex: String

        /// The label's font size, in points, set in the default font family.
        public var labelSize: Double

        /// The space kept clear between the label and each side, in points; the label
        /// is truncated with an ellipsis to fit the width left over.
        public var labelInset: Double

        /// What the label says when the node has no URL.
        public var emptyLabel: String

        /// Woodcase's placeholder: zinc-100 fill, a 1-point zinc-300 border inside the
        /// edge, and an 11-point zinc-400 label inset 12 points, reading `browser` when
        /// there is no URL.
        public static let standard = Style(
            fillHex: "#F4F4F5",
            borderHex: "#D4D4D8",
            borderWidth: 1,
            borderAlignment: .inner,
            labelHex: "#A1A1AA",
            labelSize: 11,
            labelInset: 12,
            emptyLabel: "browser"
        )

        /// The label for a browser before truncation: its URL as stored, trimmed of
        /// surrounding whitespace, or ``emptyLabel`` when that leaves nothing.
        ///
        /// - Parameter data: The browser's payload.
        /// - Returns: The text to draw.
        public func label(for data: PenNode.BrowserData) -> String {
            let url = (data.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? emptyLabel : url
        }
    }
}
