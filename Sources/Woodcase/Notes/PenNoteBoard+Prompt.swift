//
//  PenNoteBoard+Prompt.swift
//  Woodcase
//

import Foundation

public extension PenNoteBoard {
    /// One prompt, and where its run stands in the queue.
    ///
    /// Run queues work in the file (Penumbra's notes design rev 2, decision 14): Run sets
    /// `woodcase.state: queued` and `woodcase.requestedBy`; a watching agent claims it by
    /// writing `running`, answers in a comment thread anchored to the prompt, and writes
    /// `done`. A prompt with no state has never been run.
    struct Prompt: Friendly {
        /// The prompt's id.
        public var id: String

        /// The prompt's revision, as `tree --json` prints it: quote it on `--rev` when
        /// claiming the run, so two agents cannot both claim it.
        public var rev: String

        /// The prompt's name, when it has one.
        public var name: String?

        /// Where its run stands as written — `queued`, `running`, `done`, or a
        /// misspelling — or `nil` for a prompt never run.
        public var state: String?

        /// Who pressed Run.
        public var requestedBy: String?

        /// Who wrote the prompt.
        public var author: String?

        /// The model the prompt names, when it names one.
        public var model: String?

        /// The prompt's markdown, as its `content` holds it.
        public var content: String

        /// The first line of its words, with the markdown syntax removed.
        public var firstLine: String

        /// Creates a prompt row.
        ///
        /// - Parameters:
        ///   - id: The prompt's id.
        ///   - rev: The prompt's revision.
        ///   - name: The prompt's name.
        ///   - state: Where its run stands, as written.
        ///   - requestedBy: Who pressed Run.
        ///   - author: Who wrote it.
        ///   - model: The model it names.
        ///   - content: Its markdown.
        ///   - firstLine: The first line of its words.
        public init(
            id: String,
            rev: String,
            name: String?,
            state: String?,
            requestedBy: String?,
            author: String?,
            model: String?,
            content: String,
            firstLine: String
        ) {
            self.id = id
            self.rev = rev
            self.name = name
            self.state = state
            self.requestedBy = requestedBy
            self.author = author
            self.model = model
            self.content = content
            self.firstLine = firstLine
        }
    }
}
