//
//  PenComment+Write.swift
//  Woodcase
//

import Foundation

public extension PenComment {
    /// One comment write, ready to apply: the operation, and the thread and message it
    /// touches, so the caller can answer with them without reading the document again.
    struct Write: Friendly {
        /// The edit: an `insertNode` at the root for a new message, a `setProperties` of
        /// the deep key `common.metadata.woodcase.state` for a state change — apply it
        /// through a ``DocumentSession`` or an ``ActivityRecorder``, which fold deep keys.
        public var operation: EditOperation

        /// The thread's id: its first message's.
        public var threadID: String

        /// The message written: the new note, or for a state change the first message.
        public var messageID: String

        /// Creates a write.
        ///
        /// - Parameters:
        ///   - operation: The edit.
        ///   - threadID: The thread's first message's id.
        ///   - messageID: The message written.
        public init(operation: EditOperation, threadID: String, messageID: String) {
            self.operation = operation
            self.threadID = threadID
            self.messageID = messageID
        }
    }

    /// Why a comment write was refused.
    enum WriteError: Error, Friendly {
        /// The id given as a thread names no comment message: no node, or a node that is
        /// not a comment.
        ///
        /// - Parameters:
        ///   - id: The id given.
        ///   - threads: The document's threads, by first message id, in document order.
        case notAComment(id: String, threads: [String])

        /// The thread's first message is gone, so there is no state to set: only replies
        /// name it.
        ///
        /// - Parameters:
        ///   - threadID: The id the replies name.
        ///   - reply: The reply the write was asked on.
        case firstMessageMissing(threadID: String, reply: String)

        /// The message has no words in it.
        case emptyMessage

        /// The refusal as one message: what was refused, the valid choices, and what to
        /// run instead.
        public var message: String {
            switch self {
            case let .notAComment(id, threads):
                let choices = threads.isEmpty
                    ? "The file has no comment threads; start one with `woodcase comment`."
                    : "Its threads: \(threads.joined(separator: ", ")). `woodcase comments` lists them with their text."
                return "\(id) is not a comment message in this file. \(choices)"
            case let .firstMessageMissing(threadID, reply):
                return "\(reply) replies to \(threadID), which is gone, so the thread has no first message to hold "
                    + "its state. Start a new thread with `woodcase comment`, or reply to keep the conversation."
            case .emptyMessage:
                return "A comment needs text: give it as the last argument, or with -F <file> (`-F -` reads "
                    + "standard input)."
            }
        }
    }
}
