//
//  ActivityReader.swift
//  Woodcase
//

import Foundation

/// Reads an ``ActivityLog`` forward from a byte offset, so a follower never sees the
/// same event twice.
///
/// The reader is the other half of the log's contract with the viewer and the CLI. It
/// decodes whole lines only, filters by file and identity, and hands back the offset to
/// resume from:
///
/// ```swift
/// let reader = ActivityReader(log: ActivityLogLocation.log(for: url))
/// var page = try reader.read(file: url)
/// for event in page.events { show(event) }
/// // later …
/// page = try reader.read(from: page.nextOffset, file: url)
/// ```
///
/// Those two calls read the **live file only** — `activity.jsonl`, not the archives
/// rotation moved aside — so on a long history they see only the newest part of it.
/// ``read(after:file:identity:)`` from ``ActivityCursor/start`` reads every archive and
/// then the live file.
///
/// ## A bundle's history
///
/// A bundle's log is one file per writer (``ActivityLog/Layout/perWriter``), and every
/// read here merges them: rows come back in time order, a tie going to the writer whose
/// file name sorts first, each writer's own rows in the order it appended them (see
/// ``HistoryFiles``). Each row's ``ActivityEvent/file``, which the history does not
/// store, is filled in with the bundle's document as it is named now. Its positions are
/// per-writer ``ActivityCursor``s; a byte offset means nothing across several files, so
/// resume a bundle's history with ``Page/cursor`` and ``read(after:file:identity:)``, not
/// with ``Page/nextOffset``.
///
/// ## No lock, on purpose
///
/// A writer appends whole lines under an exclusive lock, but a reader takes no lock at
/// all: it stops at the last newline in the file, so a line a writer is halfway through
/// is simply not consumed yet, and the next read picks it up complete. That makes
/// following the log free of any contention with the process doing the editing.
///
/// ## Rotation
///
/// ``ActivityLog`` renames the live file aside when it grows past its threshold. A
/// follower holding only a byte offset notices because the file it resumes into is
/// *shorter* than the offset; the reader then starts from zero and sets
/// ``Page/restarted``. That heuristic loses events if the fresh log outgrows the old
/// offset between two polls, so a follower that cannot afford a gap holds an
/// ``ActivityCursor`` — offset plus inode — and reads with ``read(after:file:identity:)``,
/// which finds the rotated file by inode and loses nothing.
public struct ActivityReader: Friendly {
    /// Reads the given log.
    ///
    /// - Parameter log: The log to read. There is no default: which log to read depends
    ///   on which .pen file (or which directory) the caller means, and
    ///   ``ActivityLogLocation`` is where that is decided.
    public init(log: ActivityLog) {
        self.log = log
    }

    /// The log being read.
    public let log: ActivityLog

    /// What one read produced, and where to resume.
    public struct Page: Friendly {
        /// Creates a page.
        ///
        /// - Parameters:
        ///   - events: The events read, after filtering, in log order.
        ///   - nextOffset: The byte offset to resume from.
        ///   - restarted: Whether the log had been rotated since the last read.
        ///   - skippedLines: How many lines could not be decoded.
        ///   - cursor: The position to resume from; `nil` when the page was not read
        ///     from a log file.
        ///   - eventCursors: The position just after each of `events`, in the same order.
        public init(
            events: [ActivityEvent],
            nextOffset: UInt64,
            restarted: Bool,
            skippedLines: Int,
            cursor: ActivityCursor? = nil,
            eventCursors: [ActivityCursor] = []
        ) {
            self.events = events
            self.nextOffset = nextOffset
            self.restarted = restarted
            self.skippedLines = skippedLines
            self.cursor = cursor
            self.eventCursors = eventCursors
        }

        /// Where to resume, naming the file by inode so a rotation in between is
        /// survivable: pass it to ``ActivityReader/read(after:file:identity:)``.
        public var cursor: ActivityCursor?

        /// The position just after each of ``events``, in the same order, so a consumer
        /// that stops part-way through a page can resume exactly after the last event
        /// it took.
        public var eventCursors: [ActivityCursor]

        /// The events read, after filtering, in the order they were appended.
        public var events: [ActivityEvent]

        /// The offset just past the last complete line, to pass to the next read.
        ///
        /// It counts every complete line the read covered, filtered out or not, so a
        /// filtered follower still advances past events it does not care about. Always
        /// zero for a bundle's history, which has no single offset: resume it with
        /// ``cursor``.
        public var nextOffset: UInt64

        /// Whether the log was rotated and this read started over from its beginning.
        ///
        /// A follower that shows a continuous feed should treat this as "the history
        /// before here has moved to an archive file", not as new activity.
        ///
        /// A read from an ``ActivityCursor`` (``ActivityReader/read(after:file:identity:)``)
        /// sets it only when the cursor could not be followed — its archive is gone — so
        /// events between the cursor and the live log may have been missed. Crossing a
        /// rotation the cursor *can* follow loses nothing and is not a restart.
        public var restarted: Bool

        /// How many complete lines could not be decoded as events.
        ///
        /// A line written by a newer, incompatible version — or a scrap left by a
        /// crash — is counted here and stepped over rather than stopping the reader
        /// forever at the same byte.
        public var skippedLines: Int
    }

    /// Reads every complete line of the **live file** from `offset` on — never the
    /// rotated archives.
    ///
    /// With the default offset this is the live file from its first byte, which is the
    /// whole history only until the log first rotates (``ActivityLog/rotationThreshold``);
    /// after that the older rows are in archives this call does not open. To read every
    /// retained row, use ``read(after:file:identity:)`` from ``ActivityCursor/start``; to
    /// cost or test a full-history read, time that call, not this one.
    ///
    /// - Parameters:
    ///   - offset: Where to start, from a previous ``Page/nextOffset``. Zero reads the
    ///     live file from its beginning — in a bundle, every writer's live file. A bundle
    ///     has no other offset to give: anything else reads from its end.
    ///   - file: Show only events for this .pen file. Compared as
    ///     ``ActivityEvent/canonicalPath(for:)``, so any spelling of the path matches.
    ///   - identity: Show only events written by this `--as` name.
    /// - Returns: The matching events and the offset to resume from. A log that does not
    ///   exist yet reads as an empty page rather than an error — nothing has been
    ///   logged, which is not a failure.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the log exists but cannot
    ///   be read.
    public func read(
        from offset: UInt64 = 0,
        file: URL? = nil,
        identity: String? = nil
    ) throws -> Page {
        switch log.layout {
        case .single:
            try readFile(at: log.fileURL, from: offset, file: file, identity: identity)
        case .perWriter:
            try read(after: liveCursor(atOffset: offset), file: file, identity: identity)
        }
    }

    /// The last `count` matching events in the live file; rows rotated into archives are
    /// not considered.
    ///
    /// - Parameters:
    ///   - count: How many events to return. The whole log if it holds fewer.
    ///   - file: Show only events for this .pen file.
    ///   - identity: Show only events written by this `--as` name.
    /// - Returns: The most recent matching events, oldest first.
    /// - Throws: Whatever ``read(from:file:identity:)`` throws.
    public func tail(count: Int, file: URL? = nil, identity: String? = nil) throws -> [ActivityEvent] {
        guard count > 0 else { return [] }
        let page = try read(file: file, identity: identity)
        return Array(page.events.suffix(count))
    }

    /// The newest event recorded for one file, read from the end of the log.
    ///
    /// The one question a *writer* asks the log — "is the file still where the log left
    /// it?" — and the answer is always in the last few lines. Reading forward to find it
    /// would decode the whole history on every write, so this walks backwards in chunks
    /// and decodes only as far as it must: one chunk for the ordinary case, more only
    /// when the newest lines belong to other files.
    ///
    /// In a bundle's history it is the newest row of any writer, read from the end of
    /// each writer's live file.
    ///
    /// - Parameter file: The .pen file to look for. `nil` takes the newest event of any
    ///   file, which is what a caller with a single-file log wants.
    /// - Returns: The newest matching event, or `nil` when the log holds none — a log
    ///   that does not exist yet included, because nothing has been recorded, which is
    ///   not a failure.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the log exists but cannot
    ///   be read.
    public func newest(file: URL? = nil) throws -> ActivityEvent? {
        switch log.layout {
        case .single:
            try log.lines.newest(matching: matching(file: file, identity: nil))
        case .perWriter:
            try log.history.newest(matching: matching(file: file, identity: nil)).map(stamped)
        }
    }
}
