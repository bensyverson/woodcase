//
//  PenNoteBoard+Note.swift
//  Woodcase
//

import Foundation

public extension PenNoteBoard {
    /// One post-it: a plain `note` that is not a comment message.
    ///
    /// A note has no state and no kind (Ben, 2026-10-11): what tells notes apart is who
    /// wrote them, their paper and their words.
    struct Note: Friendly {
        /// The note's id.
        public var id: String

        /// The note's revision, as `tree --json` prints it.
        public var rev: String

        /// The note's name, when it has one.
        public var name: String?

        /// Who wrote it, from `woodcase.author` in either spelling.
        public var author: String?

        /// Its paper color as written, from `woodcase.tint`; `nil` is Post-it yellow.
        public var tint: String?

        /// The size it lays out at — set, defaulted, and grown to fit its text.
        public var size: PenSize?

        /// The note's markdown, as its `content` holds it.
        public var content: String

        /// The first line of its words, with the markdown syntax removed.
        public var firstLine: String

        /// Creates a note row.
        ///
        /// - Parameters:
        ///   - id: The note's id.
        ///   - rev: The note's revision.
        ///   - name: The note's name.
        ///   - author: Who wrote it.
        ///   - tint: Its paper color as written.
        ///   - size: The size it lays out at.
        ///   - content: Its markdown.
        ///   - firstLine: The first line of its words.
        public init(
            id: String,
            rev: String,
            name: String?,
            author: String?,
            tint: String?,
            size: PenSize?,
            content: String,
            firstLine: String
        ) {
            self.id = id
            self.rev = rev
            self.name = name
            self.author = author
            self.tint = tint
            self.size = size
            self.content = content
            self.firstLine = firstLine
        }
    }
}
