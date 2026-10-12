//
//  PenComment.swift
//  Woodcase
//

import Foundation

/// Writing comments: starting a thread, replying to one, and resolving or reopening it.
///
/// A comment is a note, one per message, at the document root (Penumbra's notes design
/// rev 2, decision 8); ``PenCommentThread`` is how a thread reads. These builders hold
/// every decision about how one is *written*, so neither an agent nor an app writes the
/// comment keys by hand, and `woodcase comment`, `reply` and `resolve` and Penumbra make
/// the same notes:
///
/// - A first message carries `woodcase.type: comment`, `author`, `createdAt`,
///   `state: open` and `anchor` — ``PenCommentThread/Anchor``: a node and a point in its
///   own coordinates, or a page point with no node.
/// - A reply carries `type`, `author`, `createdAt` and `replyTo`, which always names the
///   thread's first message, even when the reply was asked for on another reply.
/// - Resolving sets the first message's `state` and nothing else.
///
/// Each builder answers a ``Write``: the one ``EditOperation`` to apply, through
/// whichever door the caller edits by — an ``ActivityRecorder`` in the CLI, a
/// ``DocumentSession`` in an app — so the edit is logged and undoable like any other.
///
/// ```swift
/// let anchor = try PenComment.anchor(on: "Card/Button", x: 12, y: 4, in: document)
/// let thread = try PenComment.startThread("Too tall?", anchor: anchor, author: "ana", at: .now, in: document)
/// try recorder.apply(thread.operation)
/// let reply = try PenComment.reply("Fixed.", to: thread.messageID, author: "claude", at: .now, in: document)
/// ```
///
/// Times are UTC in the file, to the second (``createdAt(_:)``); showing them in local
/// time is the reader's business.
public enum PenComment {
    /// How `woodcase.createdAt` is spelled, for a refusal to name.
    public static let createdAtForm = "YYYY-MM-DDTHH:MM:SSZ"

    /// A time as `woodcase.createdAt` writes it: ISO 8601 in UTC, to the second.
    ///
    /// - Parameter date: The time; anything below a second is dropped.
    /// - Returns: The time, such as `2026-10-11T20:41:07Z`.
    public static func createdAt(_ date: Date) -> String {
        date.formatted(format)
    }

    /// Reads a `woodcase.createdAt` value.
    ///
    /// Only the one form Woodcase writes reads — `YYYY-MM-DDTHH:MM:SSZ`, in UTC with
    /// seconds — so an offset, a fraction or a date that does not exist, such as
    /// February 30, is refused rather than read as a time it might not mean.
    ///
    /// - Parameter text: The value as written.
    /// - Returns: The time, or `nil` when `text` is not in that form.
    public static func date(createdAt text: String) -> Date? {
        guard text.wholeMatch(of: shape) != nil, let date = try? format.parse(text) else { return nil }
        // A parse that normalizes (February 30 to March 2) would not round-trip.
        return createdAt(date) == text ? date : nil
    }

    // MARK: - Private

    /// The written form's shape; the round trip checks that the fields are in range.
    /// Computed because `Regex` is not `Sendable`, so it cannot be a static constant.
    private static var shape: Regex<Substring> {
        #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/#
    }

    /// ISO 8601 in UTC with whole seconds: `Date.ISO8601FormatStyle`'s default.
    private static let format = Date.ISO8601FormatStyle()
}
