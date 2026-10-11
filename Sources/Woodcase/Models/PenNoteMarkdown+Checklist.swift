//
//  PenNoteMarkdown+Checklist.swift
//  Woodcase
//

import Foundation

public extension PenNoteMarkdown {
    /// One checklist item: a `- [ ]` or `- [x]` line.
    struct ChecklistItem: Friendly {
        /// Whether the box is ticked: `[x]` or `[X]`.
        public var isChecked: Bool

        /// The UTF-16 range of the source's `[ ]` or `[x]`, brackets included: what a
        /// toggle rewrites.
        public var markerSourceRange: Range<Int>

        /// The UTF-16 range of the box glyph in the display text: what a click hits.
        public var boxDisplayRange: Range<Int>

        /// The UTF-16 range of the whole item in the display text, box to line end,
        /// without its newline.
        public var lineDisplayRange: Range<Int>

        /// Creates a checklist item.
        ///
        /// - Parameters:
        ///   - isChecked: Whether the box is ticked.
        ///   - markerSourceRange: The source range of `[ ]` or `[x]`.
        ///   - boxDisplayRange: The display range of the box glyph.
        ///   - lineDisplayRange: The display range of the item.
        public init(isChecked: Bool, markerSourceRange: Range<Int>, boxDisplayRange: Range<Int>, lineDisplayRange: Range<Int>) {
            self.isChecked = isChecked
            self.markerSourceRange = markerSourceRange
            self.boxDisplayRange = boxDisplayRange
            self.lineDisplayRange = lineDisplayRange
        }
    }

    /// The checklist item whose box or words a display offset falls on.
    ///
    /// - Parameter displayOffset: A UTF-16 offset into ``displayText``.
    /// - Returns: The item, or `nil` when the offset is on no checklist line.
    func checklistItem(atDisplayOffset displayOffset: Int) -> ChecklistItem? {
        checklistItems.first { $0.lineDisplayRange.contains(displayOffset) }
    }

    /// The source with one checklist item's box flipped: `[ ]` becomes `[x]` and `[x]`
    /// or `[X]` becomes `[ ]`. Nothing else in the source changes, so the edit is the
    /// three code units of ``ChecklistItem/markerSourceRange``.
    ///
    /// - Parameter item: One of ``checklistItems``.
    /// - Returns: The new source, or ``source`` unchanged when `item` is not this
    ///   note's.
    func toggling(_ item: ChecklistItem) -> String {
        guard checklistItems.contains(item) else { return source }
        var units = Array(source.utf16)
        units.replaceSubrange(item.markerSourceRange, with: Array((item.isChecked ? "[ ]" : "[x]").utf16))
        return String(decoding: units, as: UTF16.self)
    }
}
