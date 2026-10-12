//
//  PenCommentThread+Message.swift
//  Woodcase
//

import Foundation

public extension PenCommentThread {
    /// One message of a thread: one comment note.
    struct Message: Friendly {
        /// The note's id.
        public var id: String

        /// The note's revision, as `tree --json` prints it: quote it on `--rev` to edit
        /// the message only if no one else has.
        public var rev: String

        /// Who wrote it, from `woodcase.author`.
        public var author: String?

        /// On a reply, the first message's id, from `woodcase.replyTo`.
        public var replyTo: String?

        /// The note's markdown, as its `content` holds it.
        public var content: String

        /// The first line of the message's words, with the markdown syntax removed.
        public var firstLine: String

        /// The names the message `@mentions`, each once, in order
        /// (``PenNoteMarkdown/mentionedNames``).
        public var mentions: [String]

        /// Creates a message.
        ///
        /// - Parameters:
        ///   - id: The note's id.
        ///   - rev: The note's revision.
        ///   - author: Who wrote it.
        ///   - replyTo: On a reply, the first message's id.
        ///   - content: The note's markdown.
        ///   - firstLine: The first line of its words.
        ///   - mentions: The names it mentions.
        public init(
            id: String,
            rev: String,
            author: String?,
            replyTo: String?,
            content: String,
            firstLine: String,
            mentions: [String]
        ) {
            self.id = id
            self.rev = rev
            self.author = author
            self.replyTo = replyTo
            self.content = content
            self.firstLine = firstLine
            self.mentions = mentions
        }
    }
}
