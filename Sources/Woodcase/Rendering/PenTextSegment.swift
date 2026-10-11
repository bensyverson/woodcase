//
//  PenTextSegment.swift
//  Woodcase
//

import Foundation

/// A stretch of a text set in one style: the runs that cover it resolved over the node's
/// own style.
///
/// ``PenTextStyle/segments(of:runs:)`` partitions a text into these, so a renderer sets each
/// in its face and an editor reads the style under a caret or across a selection from them.
public struct PenTextSegment: Friendly {
    /// The UTF-16 range of the text this segment covers.
    public var range: Range<Int>

    /// The style its characters are set in: the node's, with the covering runs' keys over it.
    public var style: PenTextStyle

    /// The color a covering run gives its glyphs, or `nil` for the node's paint.
    public var fill: PenHexColor?

    /// The name a covering run mentions (``PenTextRun/mention``), or `nil`: what a
    /// renderer draws as a pill.
    public var mention: String?

    /// Creates a segment.
    ///
    /// - Parameters:
    ///   - range: The UTF-16 range covered.
    ///   - style: The resolved style.
    ///   - fill: A run's color, or `nil` for the node's paint.
    ///   - mention: The name a covering run mentions, or `nil`.
    public init(range: Range<Int>, style: PenTextStyle, fill: PenHexColor?, mention: String? = nil) {
        self.range = range
        self.style = style
        self.fill = fill
        self.mention = mention
    }
}
