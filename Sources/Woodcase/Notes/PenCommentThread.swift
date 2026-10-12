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
/// is about and the point on it, or a page point — and `woodcase.state`, `open` or
/// `resolved`; each reply carries `woodcase.replyTo`, the first message's id. Every
/// message carries `woodcase.author` and `woodcase.createdAt`. A thread is that first
/// message and every reply naming it, replies in `createdAt` order (document order where
/// none is written). ``PenComment`` writes them.
///
/// A reply whose first message is gone still reads, as a thread of its own with
/// ``isMissingFirstMessage`` set and its ``id`` the id the replies name — a listing
/// that dropped it would be a plausible wrong answer. A thread whose anchor names a node
/// that is gone reads too, as ``Placement/deletedNode``.
///
/// ```swift
/// let board = try PenNoteBoard(document: document)
/// for thread in board.threads(PenNoteBoard.CommentQuery(mentions: "claude")) {
///     print(thread.id, thread.placement, thread.messages.count)
/// }
/// ```
public struct PenCommentThread: Friendly {
    /// The first message's id; for a thread whose first message is gone, the id its
    /// replies name.
    public var id: String

    /// Whether the thread still asks for attention. A first message with no state is
    /// open — a new comment asks for attention — and so is one whose state is misspelled
    /// (``unrecognizedState``). `nil` only when the first message is gone.
    public var state: PenPostIt.State?

    /// The first message's state as written, when it is neither `open` nor `resolved`;
    /// the thread reads as open meanwhile.
    public var unrecognizedState: String?

    /// What the thread is about, or `nil` when the first message names nothing, names
    /// something unreadable, or is gone.
    public var anchor: Anchor?

    /// Where the thread sits: on a node, on the canvas, on a deleted node, or nowhere.
    public var placement: Placement

    /// Whether the first message is missing: only replies name this thread.
    public var isMissingFirstMessage: Bool

    /// The messages: the first, then each reply, by ``Message/createdAt``.
    public var messages: [Message]

    /// Creates a thread.
    ///
    /// - Parameters:
    ///   - id: The first message's id, or the id the replies name.
    ///   - state: The thread's state; `nil` only for a missing first message.
    ///   - unrecognizedState: The state as written when it is not a known spelling.
    ///   - anchor: What the thread is about.
    ///   - placement: Where the thread sits.
    ///   - isMissingFirstMessage: Whether the first message is gone.
    ///   - messages: The messages, first message first.
    public init(
        id: String,
        state: PenPostIt.State?,
        unrecognizedState: String? = nil,
        anchor: Anchor?,
        placement: Placement,
        isMissingFirstMessage: Bool = false,
        messages: [Message]
    ) {
        self.id = id
        self.state = state
        self.unrecognizedState = unrecognizedState
        self.anchor = anchor
        self.placement = placement
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
