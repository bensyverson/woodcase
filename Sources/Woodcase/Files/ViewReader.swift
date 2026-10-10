//
//  ViewReader.swift
//  Woodcase
//

import Foundation

/// Reads a ``ViewLog`` forward from a cursor, the way ``ActivityReader`` reads the
/// activity log: whole lines only, no lock, through rotation by inode.
///
/// ```swift
/// let reader = ViewReader(log: ViewLog(beside: ActivityLogLocation.log(for: url)))
/// var page = try reader.read(file: url)
/// for view in page.events { show(view) }
/// page = try reader.read(after: page.cursor ?? .start, file: url)
/// ```
public struct ViewReader: Friendly {
    /// Reads the given log.
    ///
    /// - Parameter log: The view log to read.
    public init(log: ViewLog) {
        self.log = log
    }

    /// The log being read.
    public let log: ViewLog

    /// What one read produced, and where to resume.
    public struct Page: Friendly {
        /// The views read, after filtering, in the order they were written.
        public var events: [ViewEvent]

        /// The position just after each of ``events``.
        public var eventCursors: [ActivityCursor]

        /// Where to resume; pass it to ``ViewReader/read(after:file:identity:)``.
        public var cursor: ActivityCursor?

        /// Whether the cursor's file had been pruned and the read began again from the
        /// live log: views in between may be missing.
        public var restarted: Bool

        /// How many complete lines could not be decoded as views.
        public var skippedLines: Int
    }

    /// Reads every view after a cursor, following it through any rotation.
    ///
    /// - Parameters:
    ///   - cursor: Where the last read ended. ``ActivityCursor/start`` reads everything.
    ///   - file: Keep only views of this document.
    ///   - identity: Keep only views by this reader.
    /// - Returns: The views in order and the cursor to resume from.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a log file exists but cannot
    ///   be read.
    public func read(after cursor: ActivityCursor = .start, file: URL? = nil, identity: String? = nil) throws -> Page {
        try Page(log.lines.read(after: cursor, matching: matching(file: file, identity: identity)))
    }

    /// The cursor at the end of the log as it is now, for a reader that wants only
    /// views written from here on.
    ///
    /// - Returns: The end of the live log, without reading it.
    public func endCursor() -> ActivityCursor {
        log.lines.endCursor()
    }

    /// Where the views at or after `date` begin, walking back from `end`: see
    /// ``JSONLinesFile/cursor(since:through:)``.
    ///
    /// - Parameters:
    ///   - date: The oldest moment in the window.
    ///   - end: Where the window ends, from ``endCursor()``.
    /// - Returns: The cursor just after the newest view stamped before `date`.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file the walk needs cannot
    ///   be read.
    func cursor(since date: Date, through end: ActivityCursor) throws -> ActivityCursor {
        try log.lines.cursor(since: date, through: end)
    }

    /// Reads the views after `cursor` up to `end` stamped at or after `date`: see
    /// ``JSONLinesFile/read(after:through:since:matching:)``.
    ///
    /// - Parameters:
    ///   - cursor: Where to start, from ``cursor(since:through:)``.
    ///   - end: Where to stop, from ``endCursor()``.
    ///   - date: Views stamped before it are dropped.
    ///   - file: Keep only views of this document.
    /// - Returns: The page, whose cursor resumes just after the last complete line read.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a log file cannot be read.
    func read(after cursor: ActivityCursor, through end: ActivityCursor, since date: Date, file: URL?) throws -> Page {
        try Page(log.lines.read(after: cursor, through: end, since: date, matching: matching(file: file, identity: nil)))
    }

    /// The filter a read applies; a bundle's log drops the file filter, as
    /// ``ActivityReader``'s does, so a renamed bundle keeps its views.
    ///
    /// - Parameters:
    ///   - file: Keep only views of this document, compared canonically.
    ///   - identity: Keep only views by this reader.
    /// - Returns: The predicate.
    private func matching(file: URL?, identity: String?) -> @Sendable (ViewEvent) -> Bool {
        let wanted = log.origin.holdsOneDocument ? nil : file.map(ActivityEvent.canonicalPath(for:))
        return { view in
            if let wanted, view.file != wanted { return false }
            if let identity, view.identity != identity { return false }
            return true
        }
    }
}

extension ViewReader.Page {
    /// Wraps a raw page of the log's lines.
    ///
    /// - Parameter page: What ``JSONLinesFile`` read.
    init(_ page: JSONLinesPage<ViewEvent>) {
        self.init(
            events: page.rows,
            eventCursors: page.rowCursors,
            cursor: page.cursor,
            restarted: page.restarted,
            skippedLines: page.skippedLines
        )
    }
}
