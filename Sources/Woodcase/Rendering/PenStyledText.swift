//
//  PenStyledText.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreGraphics
    import CoreText
    import Foundation

    /// A text set in a ``PenTextStyle``: the Core Text string, with the font and line
    /// metrics its lines are placed by.
    ///
    /// Built by ``PenTextStyle/attributedString(_:runs:indents:for:)``; ``PenTextLines`` breaks its
    /// lines and places them. ``font``, ``pitch`` and ``firstBaseline`` are the node's own
    /// style's: every line of a text without runs is set at that pitch, and a line holding a
    /// larger run grows from it (``PenTextLines/bands``). Not ``Friendly``:
    /// it holds Core Text objects, which neither encode nor cross actors.
    public struct PenStyledText {
        /// The styled string, every run carrying the style's attributes.
        public let string: CFAttributedString

        /// The resolved font of the node's own style: the font every character no run
        /// restyles is set in.
        public let font: CTFont

        /// The distance from one baseline to the next, in points
        /// (``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)``).
        public let pitch: CGFloat

        /// The first baseline's distance below the top of the text, in points
        /// (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``).
        public let firstBaseline: CGFloat

        /// The line height as a multiple of each font's size, or `nil` for each font's
        /// natural line height: what sets a run's own pitch when it is in another face.
        public let lineHeight: Double?

        /// Creates a styled text from its parts.
        ///
        /// - Parameters:
        ///   - string: The styled string.
        ///   - font: The font it is set in.
        ///   - pitch: The line pitch in points.
        ///   - firstBaseline: The first baseline below the top, in points.
        ///   - lineHeight: The line height as a multiple of the font size, or `nil` for natural.
        public init(
            string: CFAttributedString, font: CTFont, pitch: CGFloat, firstBaseline: CGFloat, lineHeight: Double?
        ) {
            self.string = string
            self.font = font
            self.pitch = pitch
            self.firstBaseline = firstBaseline
            self.lineHeight = lineHeight
        }
    }
#endif
