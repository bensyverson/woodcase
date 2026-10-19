//
//  ChangeFeed.swift
//  Woodcase
//

import Foundation

/// What changed in one .pen file since an identity last looked: others' edits, with
/// their new values, and where to resume.
///
/// The turn-based half of collaboration. An agent edits, a person reacts in an editor,
/// and on its next turn the agent asks the feed what happened in between:
///
/// ```swift
/// let feed = ChangeFeed(file: url, identity: "claude")
/// let report = try await feed.read()          // since the stored cursor
/// for row in report.changes {
///     for change in row.changes { print(row.identity, change.line) }
/// }
/// try await feed.save(report)                 // the next read starts here
/// ```
///
/// - **Others only** by default (``Writers/others``): an identity already knows what
///   it did. ``Writers/everyone`` includes its own rows.
/// - **Resumable**: ``read(from:)`` starts at the identity's cursor in an
///   ``ActivityCursorStore``; ``save(_:)`` moves it to the report's end. A read that is
///   not saved is a peek. A first look — no cursor stored — starts at the log's end and
///   says so (``Report/Origin/firstLook``), because a feed that opened with the whole
///   history would bury the turn's news.
/// - **Exact about outside writes**: the document is read under a shared lock, which a
///   woodcase write holds from its file write to its log append, so ``Report/unlogged``
///   is never a write caught halfway.
///
/// `woodcase changes` is this type with a command line around it.
public struct ChangeFeed: Friendly {
    /// Whose rows a feed lists.
    public enum Writers: String, Friendly {
        /// Every writer but the feed's own identity.
        case others
        /// Every writer, the feed's own identity included.
        case everyone
    }

    /// Where a read starts.
    public enum Start: Friendly {
        /// The identity's stored cursor, or the log's end on a first look.
        case stored
        /// A cursor the caller holds, from an earlier ``Report/cursor``.
        case cursor(ActivityCursor)
    }

    /// A feed of one file, for one identity.
    ///
    /// - Parameters:
    ///   - file: The .pen file, or a bundle.
    ///   - identity: Who is looking — the `--as` name.
    ///   - writers: Whose rows to list.
    ///   - log: The log to read; `nil` for the file's own (``ActivityLogLocation``).
    public init(file: URL, identity: String, writers: Writers = .others, log: ActivityLog? = nil) {
        self.file = PenLocation(file).document
        self.identity = identity
        self.writers = writers
        self.log = log ?? ActivityLogLocation.log(for: file)
    }

    /// The .pen document the feed reads.
    public let file: URL

    /// Who is looking.
    public let identity: String

    /// Whose rows the feed lists.
    public let writers: Writers

    /// The log the feed reads and the cursor store lives beside.
    public let log: ActivityLog

    /// Reads what changed since a start.
    ///
    /// - Parameter start: Where to begin; the stored cursor by default.
    /// - Returns: The rows, the document's revision now, and the cursor to resume from.
    /// - Throws: ``PenFileError`` when the file or the log cannot be read,
    ///   ``PenParserError`` when the file is not a .pen document.
    public func read(from start: Start = .stored) async throws -> Report {
        let reader = ActivityReader(log: log)
        let since: ActivityCursor
        let origin: Report.Origin
        switch start {
        case let .cursor(cursor):
            (since, origin) = (cursor, .given)
        case .stored:
            if let stored = try store.cursor(identity: identity, file: file) {
                (since, origin) = (stored, .stored)
            } else {
                (since, origin) = (reader.endCursor(), .firstLook)
            }
        }

        // Under the document's shared lock: a woodcase write holds it exclusively from
        // its file write to its log append, so the file and the log agree here.
        let lock = try await FileLock.acquire(file, mode: .shared, timeout: PenFileTransaction.defaultTimeout)
        defer { lock.release() }
        let revision = try EditableDocument(from: PenFileTransaction.parse(lock)).documentRevision
        let lineage = try LogLineage.read(file, at: revision, from: log)
        let page = try reader.read(after: since, file: file)

        return Report(
            file: ActivityEvent.canonicalPath(for: file),
            identity: identity,
            revision: revision,
            since: since,
            cursor: page.cursor ?? since,
            origin: origin,
            restarted: page.restarted,
            unlogged: Self.unlogged(lineage),
            changes: page.events.filter(lists).map(ActivityChangeSummary.init)
        )
    }

    /// Reads what changed since a start, waiting for a change if there is none yet.
    ///
    /// - Parameters:
    ///   - start: Where to begin; the stored cursor by default.
    ///   - timeout: How long to wait for someone else's change.
    ///   - pollInterval: How often to look while waiting.
    /// - Returns: The first non-empty report, or an empty one at the timeout.
    /// - Throws: Whatever ``read(from:)`` throws.
    public func wait(
        from start: Start = .stored, timeout: Duration, pollInterval: Duration = .milliseconds(100)
    ) async throws -> Report {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var report = try await read(from: start)
        guard report.isEmpty else { return report }

        // Cheap checks between reads: the log's new rows, and the file's stat. A full
        // read — a parse under the lock — only when one of them moved.
        let reader = ActivityReader(log: log)
        var logCursor = report.cursor
        var signature = FileSignature.read(at: file.path)
        while ContinuousClock.now < deadline {
            let remaining = ContinuousClock.now.duration(to: deadline)
            do {
                try await Task.sleep(for: min(pollInterval, remaining))
            } catch {
                return report
            }
            let page = try reader.read(after: logCursor, file: file)
            logCursor = page.cursor ?? logCursor
            let current = FileSignature.read(at: file.path)
            guard page.events.contains(where: lists) || current != signature else { continue }
            signature = current
            var next = try await read(from: .cursor(report.since))
            next.origin = report.origin
            report = next
            if !report.isEmpty { return report }
        }
        return report
    }

    /// Stores a report's end as the identity's cursor, so the next ``read(from:)``
    /// starts there.
    ///
    /// - Parameter report: The report whose ``Report/cursor`` to store.
    /// - Throws: Whatever ``ActivityCursorStore/save(_:identity:file:timeout:)`` throws.
    public func save(_ report: Report) async throws {
        try await store.save(report.cursor, identity: identity, file: file)
    }

    // MARK: - Private

    /// The store this feed's cursor lives in.
    private var store: ActivityCursorStore {
        ActivityCursorStore(log: log)
    }

    /// Whether a row belongs in this feed.
    private func lists(_ event: ActivityEvent) -> Bool {
        writers == .everyone || event.identity != identity
    }

    /// The divergence a lineage reports, or `nil` when the log explains the file.
    private static func unlogged(_ lineage: LogLineage) -> Report.Unlogged? {
        guard case let .diverged(since, found) = lineage else { return nil }
        return Report.Unlogged(since: since.revision, found: found)
    }
}
