//
//  PenTextOffsetMap.swift
//  Woodcase
//

import Foundation

/// The correspondence between a markdown source and the text it displays, in UTF-16
/// offsets on both sides.
///
/// A note's file keeps its markdown (`**bold**`, `- [ ] item`); its layout sets the
/// display text (`bold`, `☐⇥item`). The map is a list of ``Piece``s that tile both strings
/// in order. A *verbatim* piece is the same characters on both sides and maps offset for
/// offset; a *replaced* piece is syntax — removed (`**` → nothing) or drawn as a glyph
/// (`- ` → `•⇥`) — and maps as a whole.
///
/// ```swift
/// let note = PenNoteMarkdown("**Ship** it")
/// note.displayText                                       // "Ship it"
/// note.offsetMap.sourceOffset(forDisplayOffset: 0)       // 2: the "S" after "**"
/// note.offsetMap.sourceRange(forDisplayRange: 0 ..< 4)   // 2 ..< 6
/// note.offsetMap.displayOffset(forSourceOffset: 0)       // 0: hidden syntax collapses
/// ```
public struct PenTextOffsetMap: Friendly {
    /// One stretch of the source and the display text it becomes.
    public struct Piece: Friendly {
        /// The UTF-16 range of the source.
        public var source: Range<Int>

        /// The UTF-16 range of the display text; empty for syntax that is removed.
        public var display: Range<Int>

        /// Whether both sides are the same characters, mapping offset for offset.
        public var isVerbatim: Bool

        /// Creates a piece.
        ///
        /// - Parameters:
        ///   - source: The source's UTF-16 range.
        ///   - display: The display text's UTF-16 range.
        ///   - isVerbatim: Whether both sides are the same characters.
        public init(source: Range<Int>, display: Range<Int>, isVerbatim: Bool) {
            self.source = source
            self.display = display
            self.isVerbatim = isVerbatim
        }
    }

    /// The pieces, in order, tiling the source and the display text.
    public let pieces: [Piece]

    /// The source's length in UTF-16 code units.
    public let sourceLength: Int

    /// The display text's length in UTF-16 code units.
    public let displayLength: Int

    /// Creates a map from its pieces.
    ///
    /// - Parameter pieces: Pieces that tile both strings in order.
    public init(pieces: [Piece]) {
        self.pieces = pieces
        sourceLength = pieces.last?.source.upperBound ?? 0
        displayLength = pieces.last?.display.upperBound ?? 0
    }

    /// The display offset a source offset shows at.
    ///
    /// Inside verbatim text it is the same character; inside syntax it is where that
    /// syntax's display starts, so a caret in hidden `**` sits before the bold word.
    ///
    /// - Parameter sourceOffset: A UTF-16 offset into the source, clamped to it.
    /// - Returns: The UTF-16 offset into the display text.
    public func displayOffset(forSourceOffset sourceOffset: Int) -> Int {
        let offset = min(max(sourceOffset, 0), sourceLength)
        guard let piece = pieces.first(where: { $0.source.contains(offset) }) else { return displayLength }
        return piece.isVerbatim ? piece.display.lowerBound + offset - piece.source.lowerBound : piece.display.lowerBound
    }

    /// The source offset of the display character at a display offset.
    ///
    /// Hidden syntax before the character is skipped: display offset 0 of `**bold**` is
    /// source offset 2, the `b`. A glyph that stands for syntax (`•` for `- `) maps to
    /// the start of that syntax. The end of the display text is the end of the source.
    ///
    /// - Parameter displayOffset: A UTF-16 offset into the display text, clamped to it.
    /// - Returns: The UTF-16 offset into the source.
    public func sourceOffset(forDisplayOffset displayOffset: Int) -> Int {
        let offset = min(max(displayOffset, 0), displayLength)
        guard let piece = pieces.first(where: { $0.display.contains(offset) }) else { return sourceLength }
        return piece.isVerbatim ? piece.source.lowerBound + offset - piece.display.lowerBound : piece.source.lowerBound
    }

    /// The source range a display range was set from.
    ///
    /// Its start maps as ``sourceOffset(forDisplayOffset:)``; its end is just past the
    /// source of its last character, so `bold` in `**bold**` is the source `bold`, not
    /// its asterisks.
    ///
    /// - Parameter displayRange: A UTF-16 range of the display text, clamped to it.
    /// - Returns: The UTF-16 range of the source.
    public func sourceRange(forDisplayRange displayRange: Range<Int>) -> Range<Int> {
        let lower = sourceOffset(forDisplayOffset: displayRange.lowerBound)
        let end = min(max(displayRange.upperBound, 0), displayLength)
        guard end > displayRange.lowerBound,
              let piece = pieces.last(where: { $0.display.lowerBound < end && end <= $0.display.upperBound })
        else { return lower ..< lower }
        let upper = piece.isVerbatim ? piece.source.lowerBound + end - piece.display.lowerBound : piece.source.upperBound
        return lower ..< max(lower, upper)
    }

    /// The display range a source range shows as, each end mapped by
    /// ``displayOffset(forSourceOffset:)``.
    ///
    /// - Parameter sourceRange: A UTF-16 range of the source.
    /// - Returns: The UTF-16 range of the display text; empty when the source range is
    ///   only hidden syntax.
    public func displayRange(forSourceRange sourceRange: Range<Int>) -> Range<Int> {
        let lower = displayOffset(forSourceOffset: sourceRange.lowerBound)
        let upper = displayOffset(forSourceOffset: sourceRange.upperBound)
        return lower ..< max(lower, upper)
    }
}
