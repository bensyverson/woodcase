//
//  PenTextGeometry.swift
//  Woodcase
//

import Foundation

/// Where a laid-out text's carets, lines and selections are: what an editor needs to put
/// a caret on the line that was drawn, find the character under the pointer, and paint a
/// selection.
///
/// A plain value, built by ``PenTextLayout/geometry`` from the same lines every renderer
/// draws, and needing nothing but Foundation once built: keep it, send it across actors,
/// encode it. Coordinates are node-local — origin at the box's top-left, y growing
/// downward, in points — so an editor maps a view point into it through the node's world
/// transform and back. String positions are UTF-16 offsets, as `NSRange` and
/// `NSTextInputClient` count them.
///
/// Every line is a band one line pitch tall (``Line/band``), and the bands tile the block,
/// so a caret is as tall as its line's pitch and a selection spanning lines leaves no gap
/// between them. A caret stands only at a grapheme-cluster boundary: no query answers an
/// index inside a surrogate pair, a combining sequence or an emoji ZWJ sequence.
///
/// Two lines are synthesized that Core Text does not set: an empty text has one empty line
/// for its caret, at Pen's first baseline, placed as a one-line block; and a text ending in
/// a newline has an empty line after it. Neither draws anything. Carets of lines that
/// overflow a fixed-height box lie past the box, as those lines are drawn there.
///
/// Word and paragraph boundaries are not here: an editor takes them from the platform's
/// text system.
public struct PenTextGeometry: Friendly {
    /// The box the text was placed in.
    public var box: PenSize

    /// The text's length in UTF-16 code units: the last caret index.
    public var length: Int

    /// The lines, top to bottom, including the synthesized ones. Never empty.
    public var lines: [Line]

    /// Creates a geometry from its lines.
    ///
    /// - Parameters:
    ///   - box: The box the text was placed in.
    ///   - length: The text's length in UTF-16 code units.
    ///   - lines: The lines, top to bottom; at least one.
    public init(box: PenSize, length: Int, lines: [Line]) {
        self.box = box
        self.length = length
        self.lines = lines
    }

    /// Which side of a soft line break a caret index belongs to.
    ///
    /// At a soft wrap one index is both the end of a line and the start of the next, as in
    /// `NSTextView`: `.upstream` puts the caret at the end of the earlier line (after the
    /// End key, or a click past the line's end), `.downstream` at the start of the later
    /// one. Anywhere else both name the same caret.
    public enum Affinity: String, Friendly, CaseIterable {
        /// With the text before the index: the end of the earlier line at a soft wrap.
        case upstream
        /// With the text after the index: the start of the later line at a soft wrap.
        case downstream
    }

    /// A caret position: an index and the side of a soft wrap it is on.
    public struct Position: Friendly {
        /// The UTF-16 offset, always at a grapheme-cluster boundary.
        public var index: Int

        /// Which line the index belongs to at a soft wrap.
        public var affinity: Affinity

        /// Creates a position.
        ///
        /// - Parameters:
        ///   - index: The UTF-16 offset.
        ///   - affinity: The side of a soft wrap it is on.
        public init(index: Int, affinity: Affinity = .downstream) {
            self.index = index
            self.affinity = affinity
        }
    }
}
