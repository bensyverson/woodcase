//
//  PenClip+Origin.swift
//  Woodcase
//

import Foundation

public extension PenClip {
    /// Where one copied root came from in the document it was copied out of: what a Paste
    /// in Place reads to put it back (``PasteTarget/whereCopied(documentID:)``), or at the
    /// same place in another board (``PasteTarget/atBoardOffset(in:)``).
    ///
    /// Every offset is the point the root's `x` and `y` named, as drawn — its own origin,
    /// so a node a stack placed records where the stack put it, and a turned node its
    /// anchor rather than its bounds.
    struct Origin: Friendly {
        /// Creates an origin from its parts.
        ///
        /// - Parameters:
        ///   - parentID: The parent it was copied out of, or `nil` for the top level.
        ///   - offset: Its offset in that parent, or `nil` for the top level.
        ///   - boardID: Its board — its top-level ancestor — or `nil` for the top level.
        ///   - boardOffset: Its offset from the board's top-left corner, or from the
        ///     canvas origin for the top level.
        ///   - nodeID: The id it had in the document it was copied out of.
        ///   - index: Its place among its parent's children, or among the roots.
        ///   - width: The width it had, when the clip writes it at its drawn size instead.
        ///   - height: The height it had, when the clip writes it at its drawn size instead.
        public init(
            parentID: String?,
            offset: PenPoint?,
            boardID: String?,
            boardOffset: PenPoint,
            nodeID: String? = nil,
            index: Int? = nil,
            width: PenSizing? = nil,
            height: PenSizing? = nil
        ) {
            self.parentID = parentID
            self.offset = offset
            self.boardID = boardID
            self.boardOffset = boardOffset
            self.nodeID = nodeID
            self.index = index
            self.width = width
            self.height = height
        }

        /// The parent it was copied out of, or `nil` for a root copied from the top level.
        ///
        /// A stored node's id when the root was stored there. A node drawn inside an
        /// instance records the expanded id of the node it was drawn under, which a paste
        /// cannot write into, so a paste back where it came from falls back as it does for
        /// a deleted parent.
        public var parentID: String?

        /// Its offset in ``parentID``, in the parent's coordinates, or `nil` for the top
        /// level.
        public var offset: PenPoint?

        /// Its board: the stored root above it, or `nil` for a root copied from the top
        /// level. A node drawn inside an instance names the board its instance sits in.
        public var boardID: String?

        /// Its offset from ``boardID``'s top-left corner, in the board's coordinates; for a
        /// root copied from the top level, from the canvas origin — its canvas position.
        public var boardOffset: PenPoint

        /// The id it had in the document it was copied out of — a stored node's own id, or
        /// the expanded id of a node drawn inside an instance — which a paste back where it
        /// came from puts the copy right after, as Duplicate does.
        public var nodeID: String?

        /// Its place among ``parentID``'s children — among the roots for the top level — or
        /// `nil` for a node drawn inside an instance. A paste back where it came from takes
        /// it when the source node is gone.
        public var index: Int?

        /// The width it had where it came from, when that filled its container: the clip
        /// writes it as the number it was drawn at, so the clip draws on its own, and a
        /// paste writes this back where the new parent lays the copy out
        /// (``PenClip/plan(into:at:)``). `nil` when the clip's own width is the original.
        public var width: PenSizing?

        /// The height it had where it came from, when that filled its container; as
        /// ``width``.
        public var height: PenSizing?
    }
}
