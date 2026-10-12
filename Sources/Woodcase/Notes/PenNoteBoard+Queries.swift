//
//  PenNoteBoard+Queries.swift
//  Woodcase
//

import Foundation

public extension PenNoteBoard {
    /// Which notes to list.
    struct NoteQuery: Friendly {
        /// Keep only this author's notes; `nil` keeps every note.
        public var author: String?

        /// Creates a query.
        ///
        /// - Parameter author: Keep only this author's notes.
        public init(author: String? = nil) {
            self.author = author
        }
    }

    /// Which comment threads to list.
    struct CommentQuery: Friendly {
        /// The threads a state filter keeps.
        public enum State: String, Friendly, CaseIterable {
            /// Threads that still ask for attention.
            case open
            /// Threads someone resolved.
            case resolved
            /// Every thread, whatever its state.
            case all
        }

        /// Keep threads in which any message mentions this name.
        public var mentions: String?

        /// Keep threads in this state; `nil` takes ``effectiveState``'s default.
        public var state: State?

        /// Keep threads in which this author wrote any message.
        public var author: String?

        /// Creates a query.
        ///
        /// - Parameters:
        ///   - mentions: Keep threads that mention this name.
        ///   - state: Keep threads in this state.
        ///   - author: Keep threads this author wrote in.
        public init(mentions: String? = nil, state: State? = nil, author: String? = nil) {
            self.mentions = mentions
            self.state = state
            self.author = author
        }

        /// The state the query keeps: the one named, else ``State/open`` when asking for
        /// mentions — an agent looks for what still asks for it (decision 7, "open only")
        /// — else ``State/all``.
        public var effectiveState: State {
            state ?? (mentions == nil ? .all : .open)
        }
    }

    /// Which prompts to list.
    struct PromptQuery: Friendly {
        /// The prompts a state filter keeps.
        public enum State: String, Friendly, CaseIterable {
            /// Run pressed, no one has claimed it: work to take.
            case queued
            /// Claimed and under way.
            case running
            /// Answered.
            case done
            /// Every prompt, run or not.
            case all
        }

        /// Keep prompts whose run is in this state; `nil` keeps every prompt.
        public var state: State?

        /// Keep prompts this identity pressed Run on.
        public var requestedBy: String?

        /// Creates a query.
        ///
        /// - Parameters:
        ///   - state: Keep prompts whose run is in this state.
        ///   - requestedBy: Keep prompts this identity pressed Run on.
        public init(state: State? = nil, requestedBy: String? = nil) {
            self.state = state
            self.requestedBy = requestedBy
        }
    }
}
