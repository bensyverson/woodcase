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
    /// See ``JSONLinesFile/liveCursor(atOffset:)``. A bundle's history has one offset to
    /// give, zero — every writer's live file from its start; any other offset is taken as
    /// its end.
    ///
    /// - Parameter offset: A byte offset into the live log.
    /// - Returns: The cursor naming that position.
    func liveCursor(atOffset offset: UInt64) -> ActivityCursor {
        switch log.layout {
        case .single: log.lines.liveCursor(atOffset: offset)
        case .perWriter: offset == 0 ? log.history.liveStart() : log.history.endCursor()
        }
    }

    /// The cursor at the end of the log as it is now: where a reader that wants only
    /// what is appended from here on starts.
    ///
    /// - Returns: The cursor naming the end of the log.
    func endCursor() -> ActivityCursor {
        switch log.layout {
        case .single: log.lines.endCursor()
        case .perWriter: log.history.endCursor()
        }
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
        switch log.layout {
        case .single: try log.lines.cursor(since: date, through: end)
        case .perWriter: try log.history.cursor(since: date, through: end)
        }
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
        let keep = matching(file: file, identity: nil)
        return switch log.layout {
        case .single: try Page(log.lines.read(after: cursor, through: end, since: date, matching: keep))
        case .perWriter: try stamped(Page(log.history.read(after: cursor, through: end, since: date, matching: keep)))
        }
    }

    /// The newest row of each writer's live file in a bundle's history, or the newest row
    /// of a one-file log: what ``LogLineage`` asks whether any writer explains the file.
    ///
    /// - Parameter file: Keep only events for this .pen file.
    /// - Returns: At most one row per writer, in writer order.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a log file cannot be read.
    func newestPerWriter(file: URL?) throws -> [ActivityEvent] {
        switch log.layout {
        case .single: try [newest(file: file)].compactMap(\.self)
        case .perWriter: try log.history.newestPerWriter(matching: matching(file: file, identity: nil)).map(stamped)
        }
    }

    /// A bundle's row with its ``ActivityEvent/file`` filled in: the bundle's document as
    /// it is named now, since the history stores no path.
    ///
    /// - Parameter event: A row read from a bundle's history.
    /// - Returns: The row naming the document.
    func stamped(_ event: ActivityEvent) -> ActivityEvent {
        guard let document = documentPath else { return event }
        var event = event
        event.file = document
        return event
    }

    /// A page of a bundle's history with every row's ``ActivityEvent/file`` filled in.
    ///
    /// - Parameter page: The page as read.
    /// - Returns: The page naming the document.
    func stamped(_ page: Page) -> Page {
        guard let document = documentPath else { return page }
        var page = page
        for index in page.events.indices {
            page.events[index].file = document
        }
        return page
    }

    /// The canonical path of a bundle's document, or `nil` for a log that is not a
    /// bundle's.
    private var documentPath: String? {
        guard case let .bundle(root) = log.origin else { return nil }
        return ActivityEvent.canonicalPath(for: root)
    }

    /// Reads every complete line of one file of a bare file's log from `offset` on.
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
    /// A bundle's history holds only its document's rows, and names no path, so a renamed
    /// bundle keeps its history: the file filter is dropped for it.
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
