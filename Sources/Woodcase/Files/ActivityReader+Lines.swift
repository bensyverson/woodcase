//
//  ActivityReader+Lines.swift
//  Woodcase
//

import Foundation

extension ActivityReader {
    /// A cursor for a bare byte offset into the live log as it is now.
    ///
    /// How the offset-based API maps onto cursors: the offset was taken from the live
    /// file, so it names the live file's inode — or, mid-rotation, the newest archive's.
    /// See ``JSONLinesFile/liveCursor(atOffset:)``.
    ///
    /// - Parameter offset: A byte offset into the live log.
    /// - Returns: The cursor naming that position.
    func liveCursor(atOffset offset: UInt64) -> ActivityCursor {
        log.lines.liveCursor(atOffset: offset)
    }

    /// The cursor at the end of the log as it is now: where a reader that wants only
    /// what is appended from here on starts.
    ///
    /// - Returns: The cursor naming the end of the log.
    func endCursor() -> ActivityCursor {
        log.lines.endCursor()
    }

    /// Where the rows at or after `date` begin, walking back from `end`: see
    /// ``JSONLinesFile/cursor(since:through:)``.
    ///
    /// - Parameters:
    ///   - date: The oldest moment in the window.
    ///   - end: Where the window ends, from ``endCursor()``.
    /// - Returns: The cursor just after the newest row stamped before `date`.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file the walk needs cannot
    ///   be read.
    func cursor(since date: Date, through end: ActivityCursor) throws -> ActivityCursor {
        try log.lines.cursor(since: date, through: end)
    }

    /// Reads the rows after `cursor` up to `end` stamped at or after `date`: see
    /// ``JSONLinesFile/read(after:through:since:matching:)``.
    ///
    /// - Parameters:
    ///   - cursor: Where to start, from ``cursor(since:through:)``.
    ///   - end: Where to stop, from ``endCursor()``.
    ///   - date: Rows stamped before it are dropped.
    ///   - file: Show only events for this .pen file.
    /// - Returns: The page, whose cursor resumes just after the last complete line read.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a log file cannot be read.
    func read(after cursor: ActivityCursor, through end: ActivityCursor, since date: Date, file: URL?) throws -> Page {
        try Page(log.lines.read(after: cursor, through: end, since: date, matching: matching(file: file, identity: nil)))
    }

    /// Reads every complete line of one log file from `offset` on.
    ///
    /// - Parameters:
    ///   - url: The log file or one of its archives.
    ///   - offset: Where to start. An offset past the end of the file starts over from
    ///     zero and sets ``Page/restarted``: the file is not the one the offset came from.
    ///   - file: Show only events for this .pen file.
    ///   - identity: Show only events written by this `--as` name.
    /// - Returns: The page. A file that does not exist reads as an empty page whose
    ///   cursor is ``ActivityCursor/start``.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the file exists but cannot
    ///   be read.
    func readFile(at url: URL, from offset: UInt64, file: URL?, identity: String?) throws -> Page {
        try Page(log.lines.readFile(at: url, from: offset, matching: matching(file: file, identity: identity)))
    }

    /// The filter a read applies.
    ///
    /// A bundle's log holds only its document's rows, under whatever path the bundle had
    /// when each was written, so a renamed bundle keeps its history: the file filter is
    /// dropped for it.
    ///
    /// - Parameters:
    ///   - file: Keep only events for this .pen file, compared canonically.
    ///   - identity: Keep only events written by this name.
    /// - Returns: The predicate.
    func matching(file: URL?, identity: String?) -> @Sendable (ActivityEvent) -> Bool {
        let wanted = log.origin.holdsOneDocument ? nil : file.map(ActivityEvent.canonicalPath(for:))
        return { event in
            if let wanted, event.file != wanted { return false }
            if let identity, event.identity != identity { return false }
            return true
        }
    }
}

extension ActivityReader.Page {
    /// Wraps a raw page of the log's lines.
    ///
    /// - Parameter page: What ``JSONLinesFile`` read.
    init(_ page: JSONLinesPage<ActivityEvent>) {
        self.init(
            events: page.rows,
            nextOffset: page.nextOffset,
            restarted: page.restarted,
            skippedLines: page.skippedLines,
            cursor: page.cursor,
            eventCursors: page.rowCursors
        )
    }
}
