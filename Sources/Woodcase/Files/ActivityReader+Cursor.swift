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
        // A rotation can land between resolving the live inode and reading it; the page
        // then names a different inode than the one resolved, and one more pass reads
        // the file that is live now.
        var attempt = 0
        while true {
            attempt += 1
            let liveInode = FileSignature.read(at: log.fileURL.path)?.inode
            if cursor.inode != 0, cursor.inode == liveInode {
                let page = try readFile(at: log.fileURL, from: cursor.offset, file: file, identity: identity)
                if page.cursor?.inode == cursor.inode || attempt >= 3 {
                    return page
                }
                continue
            }
            return try readThroughArchives(after: cursor, file: file, identity: identity)
        }
    }

    private func readThroughArchives(
        after cursor: ActivityCursor,
        file: URL?,
        identity: String?
    ) throws -> Page {
        let archives = log.archives()
        let chain: [ActivityLog.Archive]
        var restarted = false
        if cursor.inode == 0 {
            chain = archives
        } else if let index = archives.firstIndex(where: { $0.inode == cursor.inode }) {
            chain = Array(archives[index...])
        } else {
            // The file the cursor was into is gone; whatever it held after the cursor is
            // lost, and the caller must be told.
            chain = []
            restarted = true
        }

        var merged = Page(events: [], nextOffset: 0, restarted: restarted, skippedLines: 0)
        for (position, archive) in chain.enumerated() {
            let offset = position == 0 && cursor.inode != 0 ? cursor.offset : 0
            let page = try readFile(at: archive.url, from: offset, file: file, identity: identity)
            merged.events += page.events
            merged.eventCursors += page.eventCursors
            merged.skippedLines += page.skippedLines
            merged.cursor = page.cursor
            merged.nextOffset = page.nextOffset
        }

        let live = try readFile(at: log.fileURL, from: 0, file: file, identity: identity)
        merged.events += live.events
        merged.eventCursors += live.eventCursors
        merged.skippedLines += live.skippedLines
        if FileManager.default.fileExists(atPath: log.fileURL.path) || merged.cursor == nil {
            merged.cursor = live.cursor
            merged.nextOffset = live.nextOffset
        }
        return merged
    }
}
