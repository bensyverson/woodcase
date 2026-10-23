//
//  ActivityReader+Cursor.swift
//  Woodcase
//

import Foundation

public extension ActivityReader {
    /// Reads everything after a cursor, following it through any rotation.
    ///
    /// - A cursor into the live log reads from its offset, exactly like
    ///   ``read(from:file:identity:)``.
    /// - A cursor into a file that has since been rotated resolves to the archive with
    ///   that inode, reads it from the offset, then every later archive, then the live
    ///   log from zero. Nothing is skipped and nothing is read twice, so the page does
    ///   not say ``Page/restarted``.
    /// - A cursor whose file no longer exists anywhere — the archive was pruned — reads
    ///   the live log from zero and says ``Page/restarted``: the gap is real and the
    ///   caller is told.
    /// - ``ActivityCursor/start`` reads every archive and the live log.
    /// - In a bundle's history each writer's file is read from its own position in the
    ///   cursor — from its first row when the cursor does not name it — and the rows are
    ///   merged by time. A one-file cursor from another log reads everything and says
    ///   ``Page/restarted``.
    ///
    /// - Parameters:
    ///   - cursor: Where the last read ended, from ``Page/cursor`` or ``Page/eventCursors``.
    ///   - file: Show only events for this .pen file.
    ///   - identity: Show only events written by this `--as` name.
    /// - Returns: The matching events in log order and the cursor to resume from.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a log file exists but cannot
    ///   be read.
    func read(
        after cursor: ActivityCursor,
        file: URL? = nil,
        identity: String? = nil
    ) throws -> Page {
        switch log.layout {
        case .single:
            try Page(log.lines.read(after: cursor, matching: matching(file: file, identity: identity)))
        case .perWriter:
            try stamped(Page(log.history.read(after: cursor, matching: matching(file: file, identity: identity))))
        }
    }
}
