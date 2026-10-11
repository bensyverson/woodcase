//
//  PenTextGeometry+Line.swift
//  Woodcase
//

import Foundation

public extension PenTextGeometry {
    /// One line of a laid-out text: its characters, its band and its carets.
    struct Line: Friendly {
        /// The UTF-16 range of the characters Core Text set on the line, its newline
        /// included; empty for a synthesized line.
        public var stringRange: Range<Int>

        /// The line's baseline, in points below the box's top.
        public var baseline: Double

        /// The line's band: the box-local rect its caret and its selection fill — one pitch
        /// tall, or as tall as a larger run on the line needs. Bands tile the block, top to
        /// bottom.
        public var band: PenRect

        /// Where the line starts, in points from the box's left edge: Core Text's origin
        /// after horizontal alignment.
        public var start: Double

        /// The width of the whitespace that trails the line, which alignment hangs past
        /// its edge.
        public var trailingWhitespaceWidth: Double

        /// How the line ends, which decides its last caret and how a selection across its
        /// end is drawn.
        public var ending: Ending

        /// The carets on the line, one per grapheme-cluster boundary it holds, in index
        /// order — for a line that ends in a newline, up to the newline and not after it.
        /// Never empty. Their `x` follows the text's direction, so it rises with the index
        /// in left-to-right text.
        public var carets: [Caret]

        /// Creates a line.
        ///
        /// - Parameters:
        ///   - stringRange: The UTF-16 range of the line's characters.
        ///   - baseline: The baseline below the box's top.
        ///   - band: The line's band.
        ///   - start: The line's start from the box's left edge.
        ///   - trailingWhitespaceWidth: The width of its trailing whitespace.
        ///   - ending: How it ends.
        ///   - carets: Its carets, in index order; at least one.
        public init(
            stringRange: Range<Int>,
            baseline: Double,
            band: PenRect,
            start: Double,
            trailingWhitespaceWidth: Double,
            ending: Ending,
            carets: [Caret]
        ) {
            self.stringRange = stringRange
            self.baseline = baseline
            self.band = band
            self.start = start
            self.trailingWhitespaceWidth = trailingWhitespaceWidth
            self.ending = ending
            self.carets = carets
        }

        /// How a line ends.
        public enum Ending: String, Friendly, CaseIterable {
            /// Core Text wrapped it: its last index is also the next line's first.
            case softWrap
            /// It ends in a newline: the next line starts after it, and a selection across
            /// it reaches the box's right edge.
            case hardBreak
            /// The text ends on it.
            case endOfText
        }

        /// A place a caret can stand on a line.
        public struct Caret: Friendly {
            /// The UTF-16 offset the caret stands before.
            public var index: Int

            /// The caret's x, in points from the box's left edge.
            public var x: Double

            /// Creates a caret.
            ///
            /// - Parameters:
            ///   - index: The UTF-16 offset.
            ///   - x: The x from the box's left edge.
            public init(index: Int, x: Double) {
                self.index = index
                self.x = x
            }
        }
    }
}
