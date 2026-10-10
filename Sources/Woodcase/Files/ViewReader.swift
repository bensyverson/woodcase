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
        let wanted = log.origin.holdsOneDocument ? nil : file.map(ActivityEvent.canonicalPath(for:))
        let page: JSONLinesPage<ViewEvent> = try log.lines.read(after: cursor) { view in
            if let wanted, view.file != wanted { return false }
            if let identity, view.identity != identity { return false }
            return true
        }
        return Page(
            events: page.rows,
            eventCursors: page.rowCursors,
            cursor: page.cursor,
            restarted: page.restarted,
            skippedLines: page.skippedLines
        )
    }

    /// The cursor at the end of the log as it is now, for a reader that wants only
    /// views written from here on.
    ///
    /// - Returns: The end of the live log, without reading it.
    public func endCursor() -> ActivityCursor {
        log.lines.endCursor()
    }
}
