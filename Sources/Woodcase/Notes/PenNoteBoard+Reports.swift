//
//  PenNoteBoard+Reports.swift
//  Woodcase
//

import Foundation

public extension PenNoteBoard {
    /// What `woodcase notes --json` prints.
    struct NotesReport: Friendly {
        /// The document's revision the notes were read at.
        public var revision: String
        /// The notes, in document order.
        public var notes: [Note]

        /// Creates a report.
        ///
        /// - Parameters:
        ///   - revision: The document's revision.
        ///   - notes: The notes.
        public init(revision: String, notes: [Note]) {
            self.revision = revision
            self.notes = notes
        }
    }

    /// What `woodcase comments --json` prints.
    struct CommentsReport: Friendly {
        /// The document's revision the threads were read at.
        public var revision: String
        /// The threads, in the document order of their first messages.
        public var threads: [PenCommentThread]

        /// Creates a report.
        ///
        /// - Parameters:
        ///   - revision: The document's revision.
        ///   - threads: The threads.
        public init(revision: String, threads: [PenCommentThread]) {
            self.revision = revision
            self.threads = threads
        }
    }

    /// What `woodcase prompts --json` prints.
    struct PromptsReport: Friendly {
        /// The document's revision the prompts were read at.
        public var revision: String
        /// The prompts, in document order.
        public var prompts: [Prompt]

        /// Creates a report.
        ///
        /// - Parameters:
        ///   - revision: The document's revision.
        ///   - prompts: The prompts.
        public init(revision: String, prompts: [Prompt]) {
            self.revision = revision
            self.prompts = prompts
        }
    }
}
