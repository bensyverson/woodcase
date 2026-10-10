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
    ///   - limit: Where to stop; the file's end when `nil`. Bytes after the last newline
    ///     below it are not read, exactly as a line still being written is not.
    ///   - matching: Which decoded rows to keep.
    /// - Returns: The page. A file that does not exist reads as an empty page whose
    ///   cursor is ``ActivityCursor/start``.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the file exists but cannot
    ///   be read.
    func readFile<Row: JSONLinesRow>(
        at url: URL,
        from offset: UInt64,
        through limit: UInt64? = nil,
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
            let size = try handle.seekToEnd()
            if size < offset {
                start = 0
                restarted = true
            }
            try handle.seek(toOffset: start)
            if let limit {
                let count = min(limit, size) > start ? min(limit, size) - start : 0
                data = try handle.read(upToCount: Int(count)) ?? Data()
            } else {
                data = try handle.readToEnd() ?? Data()
            }
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

    /// The cursor at the end of the file's last whole line as it is now: where a reader
    /// that wants only what comes next starts.
    ///
    /// A writer appends without the reader taking a lock, so the file's size can fall
    /// inside a line still being written. Starting there would read that line's tail as a
    /// scrap and skip it; starting at the last newline at or before the size reads it
    /// whole once it is finished. Only the file's last few bytes are read to find it.
    ///
    /// - Returns: The end of the live file's last whole line, else of the newest
    ///   archive's, else ``ActivityCursor/start``.
    func endCursor() -> ActivityCursor {
        if let live = Self.wholeLinesEnd(of: fileURL) {
            return live
        }
        if let newest = archives().last, let archive = Self.wholeLinesEnd(of: newest.url) {
            return archive
        }
        return .start
    }

    /// The position just past a file's last newline, named by the inode it was read from.
    ///
    /// - Parameter url: The live file or an archive.
    /// - Returns: The cursor, or `nil` when the file does not exist. A file that exists but
    ///   cannot be read answers its size, which is all a reader that cannot read it has.
    private static func wholeLinesEnd(of url: URL) -> ActivityCursor? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return FileSignature.read(at: url.path).map { ActivityCursor(inode: $0.inode, offset: UInt64(max(0, $0.size))) }
        }
        defer { try? handle.close() }
        guard let signature = FileSignature.read(descriptor: handle.fileDescriptor) else { return nil }
        var end = UInt64(max(0, signature.size))
        while end > 0 {
            let start = end - min(reverseChunk, end)
            guard (try? handle.seek(toOffset: start)) != nil,
                  let chunk = try? handle.read(upToCount: Int(end - start))
            else { break }
            if let last = chunk.lastIndex(of: newline) {
                let offset = start + UInt64(chunk.distance(from: chunk.startIndex, to: last)) + 1
                return ActivityCursor(inode: signature.inode, offset: offset)
            }
            end = start
        }
        return ActivityCursor(inode: signature.inode, offset: 0)
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
