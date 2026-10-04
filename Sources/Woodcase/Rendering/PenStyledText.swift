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
    /// Built by ``PenTextStyle/attributedString(_:for:)``; ``PenTextLines`` breaks its
    /// lines and places them at `pitch` from `firstBaseline`. Not ``Friendly``:
    /// it holds Core Text objects, which neither encode nor cross actors.
    public struct PenStyledText {
        /// The styled string, every run carrying the style's attributes.
        public let string: CFAttributedString

        /// The resolved font the string is set in.
        public let font: CTFont

        /// The distance from one baseline to the next, in points
        /// (``PenTextMeasurer/linePitch(lineHeight:fontSize:font:)``).
        public let pitch: CGFloat

        /// The first baseline's distance below the top of the text, in points
        /// (``PenTextMeasurer/firstBaseline(of:lineHeight:pitch:)``).
        public let firstBaseline: CGFloat

        /// Creates a styled text from its parts.
        ///
        /// - Parameters:
        ///   - string: The styled string.
        ///   - font: The font it is set in.
        ///   - pitch: The line pitch in points.
        ///   - firstBaseline: The first baseline below the top, in points.
        public init(string: CFAttributedString, font: CTFont, pitch: CGFloat, firstBaseline: CGFloat) {
            self.string = string
            self.font = font
            self.pitch = pitch
            self.firstBaseline = firstBaseline
        }
    }
#endif
