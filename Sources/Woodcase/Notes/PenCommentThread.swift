//
//  PenCommentThread.swift
//  Woodcase
//

import Foundation

/// One comment thread: a first message and its replies, read from a document's
/// comment notes.
///
/// A comment is a note, one per message (Penumbra's notes design rev 2, decision 8):
/// `woodcase.type: comment`. The first message carries `woodcase.anchor` — the node it
/// is about and the point on it — and `woodcase.state`, `open` or `resolved`; each reply
/// carries `woodcase.replyTo`, the first message's id. A thread is that first message
/// and every reply naming it, in document order.
///
/// A reply whose first message is gone still reads, as a thread of its own with
/// ``isMissingFirstMessage`` set and its ``id`` the id the replies name — a listing
/// that dropped it would be a plausible wrong answer.
///
/// ```swift
/// let board = try PenNoteBoard(document: document)
/// for thread in board.threads(PenNoteBoard.CommentQuery(mentions: "claude")) {
///     print(thread.id, thread.anchor?.node ?? "-", thread.messages.count)
/// }
/// ```
public struct PenCommentThread: Friendly {
    /// The first message's id; for a thread whose first message is gone, the id its
    /// replies name.
    public var id: String

    /// The thread's state as the first message writes it — `open` or `resolved`, or a
    /// misspelling as written. A first message with no state is open: a new comment
    /// asks for attention. `nil` only when the first message is gone.
    public var state: String?

    /// What the thread is about, or `nil` when the first message names nothing or is gone.
    public var anchor: Anchor?

    /// Whether the first message carries an anchor ``Anchor`` could not read, so a
    /// listing can say so rather than show the thread as anchored to nothing.
    public var hasUnreadableAnchor: Bool

    /// Whether the first message is missing: only replies name this thread.
    public var isMissingFirstMessage: Bool

    /// The messages: the first, then each reply, in document order.
    public var messages: [Message]

    /// Creates a thread.
    ///
    /// - Parameters:
    ///   - id: The first message's id, or the id the replies name.
    ///   - state: The state as written; `nil` only for a missing first message.
    ///   - anchor: What the thread is about.
    ///   - hasUnreadableAnchor: Whether an anchor was written that does not read.
    ///   - isMissingFirstMessage: Whether the first message is gone.
    ///   - messages: The messages, first message first.
    public init(
        id: String,
        state: String?,
        anchor: Anchor?,
        hasUnreadableAnchor: Bool = false,
        isMissingFirstMessage: Bool = false,
        messages: [Message]
    ) {
        self.id = id
        self.state = state
        self.anchor = anchor
        self.hasUnreadableAnchor = hasUnreadableAnchor
        self.isMissingFirstMessage = isMissingFirstMessage
        self.messages = messages
    }

    /// Everyone any message mentions, each once, in the order first mentioned.
    public var mentions: [String] {
        var seen: Set<String> = []
        return messages.flatMap(\.mentions).filter { seen.insert($0).inserted }
    }

    /// Everyone who wrote a message, each once, in the order they first wrote.
    public var authors: [String] {
        var seen: Set<String> = []
        return messages.compactMap(\.author).filter { seen.insert($0).inserted }
    }
}
