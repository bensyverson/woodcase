//
//  ActivityReader+Lines.swift
//  Woodcase
//

import Foundation

extension ActivityReader {
    /// A cursor for a bare byte offset into the live log as it is now.
    ///
    /// How the offset-based API maps onto cursors: the offset was taken from the live
    /// file, so it names the live file's inode.
    ///
    /// With no live file there are two cases. Archives beside it mean a rotation is
    /// mid-flight — renamed, not yet recreated — so the offset is into what is now the
    /// newest archive, and the cursor names that. With no archives either, nothing has
    /// been written and the cursor is ``ActivityCursor/start``. Mapping the first case to
    /// `start` would replay every archive.
    ///
    /// - Parameter offset: A byte offset into the live log.
    /// - Returns: The cursor naming that position.
    func liveCursor(atOffset offset: UInt64) -> ActivityCursor {
        if let inode = FileSignature.read(at: log.fileURL.path)?.inode {
            return ActivityCursor(inode: inode, offset: offset)
        }
        if let newest = log.archives().last {
            return ActivityCursor(inode: newest.inode, offset: offset)
        }
        return .start
    }

    /// Reads every complete line of one log file from `offset` on.
    ///
    /// The single place lines are decoded, shared by the live-log read and the archive
    /// reads of ``read(after:file:identity:)``.
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
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Page(
                events: [], nextOffset: 0, restarted: offset > 0, skippedLines: 0, cursor: .start
            )
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }
        defer { try? handle.close() }

        let inode = FileSignature.read(descriptor: handle.fileDescriptor)?.inode ?? 0
        var start = offset
        var restarted = false
        do {
            if try handle.seekToEnd() < offset {
                start = 0
                restarted = true
            }
            try handle.seek(toOffset: start)
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }

        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }

        // A bundle's log holds only its document's rows, under whatever path the bundle
        // had when each was written, so a renamed bundle keeps its history.
        let wanted = log.origin.holdsOneDocument ? nil : file.map(ActivityEvent.canonicalPath(for:))
        var page = Page(events: [], nextOffset: start, restarted: restarted, skippedLines: 0)
        let decoder = JSONDecoder()
        var consumed = 0
        var lineStart = data.startIndex

        while let newline = data[lineStart...].firstIndex(of: Self.newline) {
            let line = data[lineStart ..< newline]
            consumed += data.distance(from: lineStart, to: newline) + 1
            lineStart = data.index(after: newline)
            guard !line.isEmpty else { continue }

            guard let event = try? ActivityEvent(line: Data(line), using: decoder) else {
                page.skippedLines += 1
                continue
            }
            if let wanted, event.file != wanted { continue }
            if let identity, event.identity != identity { continue }
            page.events.append(event)
            page.eventCursors.append(ActivityCursor(inode: inode, offset: start + UInt64(consumed)))
        }

        page.nextOffset = start + UInt64(consumed)
        page.cursor = ActivityCursor(inode: inode, offset: page.nextOffset)
        return page
    }
}
