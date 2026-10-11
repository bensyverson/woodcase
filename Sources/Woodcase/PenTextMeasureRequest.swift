//
//  PenTextMeasureRequest.swift
//  Woodcase
//

import Foundation

/// Everything a ``TextMeasurer`` is asked to measure: a text, its style as the node writes
/// it, its styled runs and the width it may wrap at.
///
/// The style values are the node's own literals, each `nil` where the node sets none, so a
/// measurer decides the defaults the way ``PenTextStyle`` does (``PenLayoutEngine/defaultTextMeasurer``
/// does exactly that, through ``PenTextMeasurer/measure(_:fontFamily:fontSize:fontWeight:fontStyle:letterSpacing:lineHeight:maxWidth:runs:)``).
/// Being ``Friendly``, a request is also the key a cache of measured sizes keeps them by:
/// nothing outside it can change the answer, except the font set.
public struct PenTextMeasureRequest: Friendly {
    /// The string to measure.
    public var text: String

    /// The font family, or `nil` for the default.
    public var fontFamily: String?

    /// The font size in points, or `nil` for the default.
    public var fontSize: Double?

    /// The weight as the format writes it (`"bold"`, `"700"`), or `nil` for regular.
    public var fontWeight: String?

    /// The font style as the format writes it (`"italic"`), or `nil` for upright.
    public var fontStyle: String?

    /// Extra space between characters in points, or `nil` for the font's own kerning.
    public var letterSpacing: Double?

    /// The line height as a multiple of the font size, or `nil` for the font's natural one.
    public var lineHeight: Double?

    /// The width to wrap at, or `nil` for one unwrapped line per paragraph.
    public var maxWidth: Double?

    /// The text's applied styled runs (``PenNode/TextData/appliedRuns``), offsets in UTF-16
    /// code units; empty for plain text.
    public var runs: [PenTextRun]

    /// Creates a request; every style value left out is the node's default.
    ///
    /// - Parameters:
    ///   - text: The string to measure.
    ///   - fontFamily: The font family.
    ///   - fontSize: The font size in points.
    ///   - fontWeight: The weight as the format writes it.
    ///   - fontStyle: The font style as the format writes it.
    ///   - letterSpacing: Extra space between characters in points.
    ///   - lineHeight: The line height as a multiple of the font size.
    ///   - maxWidth: The width to wrap at, or `nil` for no wrapping.
    ///   - runs: The text's styled runs.
    public init(
        text: String,
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        fontWeight: String? = nil,
        fontStyle: String? = nil,
        letterSpacing: Double? = nil,
        lineHeight: Double? = nil,
        maxWidth: Double? = nil,
        runs: [PenTextRun] = []
    ) {
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.maxWidth = maxWidth
        self.runs = runs
    }

    /// This request for another text and width, its style kept.
    ///
    /// - Parameters:
    ///   - text: The string to measure instead.
    ///   - maxWidth: The width to wrap at instead.
    ///   - runs: The runs for that string.
    /// - Returns: The new request.
    public func measuring(_ text: String, maxWidth: Double?, runs: [PenTextRun]) -> PenTextMeasureRequest {
        var request = self
        request.text = text
        request.maxWidth = maxWidth
        request.runs = runs
        return request
    }
}
