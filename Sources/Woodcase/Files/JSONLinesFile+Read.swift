//
//  JSONLinesFile+Read.swift
//  Woodcase
//

import Foundation

extension JSONLinesFile {
    /// Reads every complete line of one file — the live one or an archive — from
    /// `offset` on.
    ///
    /// Takes no lock: it stops at the last newline, so a line a writer is halfway
    /// through is not consumed yet and the next read picks it up whole.
    ///
    /// - Parameters:
    ///   - url: The live file or one of its archives.
    ///   - offset: Where to start. An offset past the end of the file starts over from
    ///     zero and sets ``JSONLinesPage/restarted``: the file is not the one it came from.
    ///   - matching: Which decoded rows to keep.
    /// - Returns: The page. A file that does not exist reads as an empty page whose
    ///   cursor is ``ActivityCursor/start``.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the file exists but cannot
    ///   be read.
    func readFile<Row: JSONLinesRow>(
        at url: URL,
        from offset: UInt64,
        matching: (Row) -> Bool
    ) throws -> JSONLinesPage<Row> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return JSONLinesPage(nextOffset: 0, restarted: offset > 0, cursor: .start)
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
        let data: Data
        do {
            if try handle.seekToEnd() < offset {
                start = 0
                restarted = true
            }
            try handle.seek(toOffset: start)
            data = try handle.readToEnd() ?? Data()
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }

        var page = JSONLinesPage<Row>(nextOffset: start, restarted: restarted)
        let decoder = JSONDecoder()
        var consumed = 0
        var lineStart = data.startIndex

        while let newline = data[lineStart...].firstIndex(of: Self.newline) {
            let line = data[lineStart ..< newline]
            consumed += data.distance(from: lineStart, to: newline) + 1
            lineStart = data.index(after: newline)
            guard !line.isEmpty else { continue }

            guard let row = try? Row(line: Data(line), using: decoder) else {
                page.skippedLines += 1
                continue
            }
            guard matching(row) else { continue }
            page.rows.append(row)
            page.rowCursors.append(ActivityCursor(inode: inode, offset: start + UInt64(consumed)))
        }

        page.nextOffset = start + UInt64(consumed)
        page.cursor = ActivityCursor(inode: inode, offset: page.nextOffset)
        return page
    }

    /// Reads everything after a cursor, following it through any rotation.
    ///
    /// A cursor into the live file reads from its offset. A cursor into a rotated file
    /// resolves to the archive with that inode, reads it from the offset, then every
    /// later archive, then the live file from zero — nothing skipped, nothing twice. A
    /// cursor whose file is gone reads the live file from zero and says
    /// ``JSONLinesPage/restarted``. ``ActivityCursor/start`` reads everything.
    ///
    /// - Parameters:
    ///   - cursor: Where the last read ended.
    ///   - matching: Which decoded rows to keep.
    /// - Returns: The rows in order and the cursor to resume from.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file exists but cannot be read.
    func read<Row: JSONLinesRow>(
        after cursor: ActivityCursor,
        matching: (Row) -> Bool
    ) throws -> JSONLinesPage<Row> {
        // A rotation can land between resolving the live inode and reading it; the page
        // then names a different inode than the one resolved, and one more pass reads
        // the file that is live now.
        var attempt = 0
        while true {
            attempt += 1
            let liveInode = FileSignature.read(at: fileURL.path)?.inode
            if cursor.inode != 0, cursor.inode == liveInode {
                let page = try readFile(at: fileURL, from: cursor.offset, matching: matching)
                if page.cursor?.inode == cursor.inode || attempt >= 3 {
                    return page
                }
                continue
            }
            return try readThroughArchives(after: cursor, matching: matching)
        }
    }

    /// A cursor for a bare byte offset into the live file as it is now.
    ///
    /// With no live file there are two cases. Archives beside it mean a rotation is
    /// mid-flight — renamed, not yet recreated — so the offset is into what is now the
    /// newest archive. With no archives either, nothing has been written and the cursor
    /// is ``ActivityCursor/start``; mapping the first case there would replay every
    /// archive.
    ///
    /// - Parameter offset: A byte offset into the live file.
    /// - Returns: The cursor naming that position.
    func liveCursor(atOffset offset: UInt64) -> ActivityCursor {
        if let inode = FileSignature.read(at: fileURL.path)?.inode {
            return ActivityCursor(inode: inode, offset: offset)
        }
        if let newest = archives().last {
            return ActivityCursor(inode: newest.inode, offset: offset)
        }
        return .start
    }

    /// The cursor at the end of the file as it is now, taken from its size without
    /// reading it: where a reader that wants only what comes next starts.
    ///
    /// - Returns: The end of the live file, else of the newest archive, else
    ///   ``ActivityCursor/start``.
    func endCursor() -> ActivityCursor {
        if let live = FileSignature.read(at: fileURL.path) {
            return ActivityCursor(inode: live.inode, offset: UInt64(max(0, live.size)))
        }
        if let newest = archives().last, let archive = FileSignature.read(at: newest.url.path) {
            return ActivityCursor(inode: newest.inode, offset: UInt64(max(0, archive.size)))
        }
        return .start
    }

    /// The newest row in the live file that matches, read backwards from the end.
    ///
    /// Walks back in chunks and decodes only as far as it must: one chunk in the
    /// ordinary case, more only when the newest lines do not match.
    ///
    /// - Parameter matching: Which decoded rows count.
    /// - Returns: The newest match, or `nil` when there is none or no file yet.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the file exists but cannot
    ///   be read.
    func newest<Row: JSONLinesRow>(matching: (Row) -> Bool) throws -> Row? {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        do {
            var end = try handle.seekToEnd()
            // Bytes from the chunk below that turned out to be the head of a line this
            // chunk had only the tail of.
            var carried = Data()
            while end > 0 {
                let size = min(Self.reverseChunk, end)
                let start = end - size
                try handle.seek(toOffset: start)
                var chunk = try handle.read(upToCount: Int(size)) ?? Data()
                chunk.append(carried)
                var lines = chunk.split(separator: Self.newline, omittingEmptySubsequences: false)
                // The first segment is only a whole line when the read reached the
                // file's beginning; otherwise it continues into the chunk below.
                carried = start > 0 ? Data(lines.removeFirst()) : Data()
                for line in lines.reversed() where !line.isEmpty {
                    guard let row = try? Row(line: Data(line), using: decoder), matching(row) else {
                        continue
                    }
                    return row
                }
                end = start
            }
        } catch let error as PenFileError {
            throw error
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }
        return nil
    }

    // MARK: - Private

    /// How much ``newest(matching:)`` reads at a time. A line is a few hundred bytes,
    /// so one chunk holds hundreds and the walk almost always ends in its first read.
    private static let reverseChunk: UInt64 = 64 * 1024

    private func readThroughArchives<Row: JSONLinesRow>(
        after cursor: ActivityCursor,
        matching: (Row) -> Bool
    ) throws -> JSONLinesPage<Row> {
        let archives = archives()
        let chain: [Archive]
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

        var merged = JSONLinesPage<Row>(nextOffset: 0, restarted: restarted)
        for (position, archive) in chain.enumerated() {
            let offset = position == 0 && cursor.inode != 0 ? cursor.offset : 0
            let page = try readFile(at: archive.url, from: offset, matching: matching)
            merged.rows += page.rows
            merged.rowCursors += page.rowCursors
            merged.skippedLines += page.skippedLines
            merged.cursor = page.cursor
            merged.nextOffset = page.nextOffset
        }

        let live = try readFile(at: fileURL, from: 0, matching: matching)
        merged.rows += live.rows
        merged.rowCursors += live.rowCursors
        merged.skippedLines += live.skippedLines
        if FileManager.default.fileExists(atPath: fileURL.path) || merged.cursor == nil {
            merged.cursor = live.cursor
            merged.nextOffset = live.nextOffset
        }
        return merged
    }
}
