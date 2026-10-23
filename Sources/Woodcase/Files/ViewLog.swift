//
//  ViewLog.swift
//  Woodcase
//

import Foundation

/// The append-only JSONL file of reads: `views.jsonl`, beside a bare file's
/// `activity.jsonl`, or in a bundle's local `.woodcase/`.
///
/// One ``ViewEvent`` per line. It shares the activity log's directory, lock discipline
/// and rotation (``JSONLinesFile``) but is a separate file with its own archives
/// (`views.<timestamp>.jsonl`), because the activity log is the write history and
/// everything that reads it — ``LogLineage``, `woodcase undo`, change attribution —
/// assumes every row is a write. A view there would block an undo.
///
/// ```swift
/// let views = ViewLog(beside: ActivityLogLocation.log(for: url))
/// try await views.record(ViewEvent(identity: "claude", file: url, verb: .get,
///                                  revision: rev, nodes: [id], scope: .subtrees))
/// ```
///
/// ## Coalescing
///
/// An agent re-reads the same nodes often. ``record(_:timeout:)`` skips a view that the
/// reader's newest view of the same file already covers (``ViewEvent/covers(_:)``):
/// same revision, no new node, no wider scope. The check reads the tail of the file
/// without the lock, so two racing readers may both write — a duplicate line, which is
/// harmless — rather than make every read wait on a lock.
public struct ViewLog: Friendly {
    /// Uses an explicit directory.
    ///
    /// - Parameters:
    ///   - home: The directory the log lives in — the activity log's
    ///     ``ActivityLog/stateDirectory``. Created on first write.
    ///   - origin: Why it is that directory, as for ``ActivityLog/init(home:origin:)``.
    public init(home: URL, origin: ActivityLog.Origin = .directory) {
        self.home = home
        self.origin = origin
    }

    /// The view log kept beside an activity log, in its ``ActivityLog/stateDirectory``:
    /// a bundle's views are local state in its `.woodcase/`, not part of its shared
    /// history.
    ///
    /// - Parameter log: The activity log, from ``ActivityLogLocation``.
    public init(beside log: ActivityLog) {
        self.init(home: log.stateDirectory, origin: log.origin)
    }

    /// The log's file name inside ``home``.
    public static let fileName = "views.jsonl"

    /// The size at which the live file is moved aside before the next write.
    public static let rotationThreshold: UInt64 = 8 * 1024 * 1024

    /// The directory the log lives in.
    public let home: URL

    /// Why the log is in ``home``.
    public let origin: ActivityLog.Origin

    /// The live log file.
    public var fileURL: URL {
        home.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Records a read, unless the reader's newest view of the file already covers it.
    ///
    /// - Parameters:
    ///   - event: The read.
    ///   - timeout: How long to wait for another process to release the lock.
    /// - Returns: `true` when a line was written, `false` when it was coalesced away.
    /// - Throws: ``PenFileError`` cases naming the view log if it cannot be written.
    @discardableResult
    public func record(_ event: ViewEvent, timeout: Duration = ActivityLog.defaultTimeout) async throws -> Bool {
        let newest: ViewEvent? = try? lines.newest { (row: ViewEvent) in
            row.identity == event.identity && row.file == event.file
        }
        if let newest, newest.covers(event) { return false }

        var payload = try event.jsonLine()
        payload.append(JSONLinesFile.newline)
        try ActivityLog.prepare(home, for: origin, naming: fileURL)
        try await lines.append(payload, timeout: timeout)
        return true
    }

    // MARK: - Internal

    /// The lines file underneath.
    var lines: JSONLinesFile {
        JSONLinesFile(home: home, stem: Self.fileStem, rotationThreshold: Self.rotationThreshold)
    }

    /// The name of the live file without `.jsonl`.
    private static let fileStem = "views"
}
