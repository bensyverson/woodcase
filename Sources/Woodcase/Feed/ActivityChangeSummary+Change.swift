//
//  ActivityChangeSummary+Change.swift
//  Woodcase
//

import Foundation

public extension ActivityChangeSummary {
    /// One thing a row changed: a property, a node's place in the tree, an override, a
    /// variable, an import or a theme axis.
    ///
    /// The fields a kind of change has no use for are `nil`, and `nil` in ``old`` or
    /// ``new`` means *absent* — nothing was there before, or nothing is left after —
    /// which is not the same as a property cleared to JSON `null` (``AnyCodable/null``).
    struct Change: Friendly {
        /// Creates a change.
        ///
        /// - Parameters:
        ///   - kind: What sort of change this is, as the forward operation reads.
        ///   - node: The id of the node it is about, or `nil` for a document-level edit.
        ///   - path: That node's name path, as the row recorded it.
        ///   - key: The property path, override key, variable name, import alias or theme
        ///     axis that changed, or `nil` for a structural change.
        ///   - old: The value before, or `nil` when there was none.
        ///   - new: The value after, or `nil` when there is none.
        ///   - parent: For an insert or a move, where the node now is; for a delete,
        ///     where it was. A name path when the row recorded one, else an id.
        ///   - index: The node's index under ``parent``.
        ///   - descendant: For a descendant override, the id of the node inside the
        ///     instance that the override targets.
        public init(
            kind: ActivityEvent.Kind,
            node: String? = nil,
            path: String? = nil,
            key: String? = nil,
            old: AnyCodable? = nil,
            new: AnyCodable? = nil,
            parent: String? = nil,
            index: Int? = nil,
            descendant: String? = nil
        ) {
            self.kind = kind
            self.node = node
            self.path = path
            self.key = key
            self.old = old
            self.new = new
            self.parent = parent
            self.index = index
            self.descendant = descendant
        }

        /// What sort of change this is: the kind its own forward operation reads as,
        /// which for an `undo` or `merge` row is the edit it replayed.
        public var kind: ActivityEvent.Kind

        /// The id of the node the change is about; `nil` for a variable, an import, a
        /// theme axis or a document property.
        public var node: String?

        /// The node's name path, as the row recorded it.
        public var path: String?

        /// The property path, override key, variable name, import alias or theme axis.
        public var key: String?

        /// The value before; `nil` when there was none. A removed node's whole subtree;
        /// a moved node's former `{parent, index}`.
        public var old: AnyCodable?

        /// The value after; `nil` when there is none. An inserted node's whole subtree;
        /// a moved node's new `{parent, index}`.
        public var new: AnyCodable?

        /// Where an inserted or moved node now is, or where a deleted one was.
        public var parent: String?

        /// The node's index under ``parent``.
        public var index: Int?

        /// The node inside an instance that a descendant override targets.
        public var descendant: String?

        /// The change as one line, without the time and writer a feed prints beside it.
        ///
        /// ```text
        /// Home/Hero/Title  kind.content: "Welcome" → "Welcome back"
        /// Home/Note  added text "Warmer, please" in Home at 2
        /// var --accent: "#FF8800" → "#FF0000"
        /// ```
        public var line: String {
            LineText(self).text
        }
    }
}
