//
//  PenPostItExpansion+Checkbox.swift
//  Woodcase
//

import Foundation

public extension PenPostItExpansion {
    /// One checklist box the body draws: the item it toggles and where it is.
    ///
    /// The box is a ``Role/checkbox`` shape part with the same ``frame``; an editor
    /// hit-tests a click against the frame and writes
    /// ``PenNoteMarkdown/toggling(_:)`` of the ``item``.
    struct Checkbox: Friendly {
        /// The checklist item, as the note's markdown parsed it.
        public var item: PenNoteMarkdown.ChecklistItem
        /// The box, in the node's own coordinates: the toggle's hit rect.
        public var frame: PenRect

        /// Creates a checkbox.
        ///
        /// - Parameters:
        ///   - item: The checklist item.
        ///   - frame: The box, in the node's own coordinates.
        public init(item: PenNoteMarkdown.ChecklistItem, frame: PenRect) {
            self.item = item
            self.frame = frame
        }
    }
}
