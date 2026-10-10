//
//  JSONLinesFile+Since.swift
//  Woodcase
//

import Foundation

extension JSONLinesFile {
    /// Where the rows written at or after `date` begin: the position just after the newest
    /// row, at or before `end`, stamped before `date` by more than ``stampSlack``.
    ///
    /// Walks backward from `end` in chunks, reading only the stamp of each line, so the
    /// cost is the window's, not the history's. It opens the archives — newest first —
    /// only when every row of the file it is in is inside the window. Rows are appended in
    /// time order only up to the moment between a writer stamping a row and taking the
    /// lock, so a row a moment older than `date` can sit in front of one inside the
    /// window; the walk steps past rows within the slack and stops at the first clearly
    /// older one. The cursor may therefore sit a few rows before the window, which is why
    /// ``read(after:through:since:matching:)`` filters by time.
    ///
    /// - Parameters:
    ///   - date: The oldest moment in the window.
    ///   - end: Where the window ends: a cursor from ``endCursor()``. The walk never looks
    ///     past it, so the answer is never after it.
    /// - Returns: The cursor just after the newest clearly older row; ``ActivityCursor/start``
    ///   when every retained row is in the window, or when `end`'s file can no longer be
    ///   found; `end` itself when no row before it is.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file the walk needs exists
    ///   but cannot be read.
    func cursor(since date: Date, through end: ActivityCursor) throws -> ActivityCursor {
        guard end.inode != 0 else { return .start }
        // A rotation between listing the files and opening the live one hands the walk a
        // file with another inode; listing again finds the one it meant among the archives.
        for _ in 0 ..< Self.attempts {
            let files = everyFile()
            guard let last = files.lastIndex(where: { $0.inode == end.inode }) else { return .start }
            var index = last
            var raced = false
            while index >= 0 {
                let file = files[index]
                let found = try offsetAfterNewestRow(
                    before: date.addingTimeInterval(-Self.stampSlack),
                    in: file,
                    below: index == last ? end.offset : nil
                )
                switch found {
                case let .found(offset):
                    return ActivityCursor(inode: file.inode, offset: offset)
                case .none:
                    index -= 1
                case .replaced:
                    raced = true
                }
                if raced { break }
            }
            if !raced { return .start }
        }
        return .start
    }

    /// Reads every complete line after `cursor` up to `end`, keeping the rows stamped at
    /// or after `date`.
    ///
    /// The history half of a follower that starts at a time: it reads through the archives
    /// as ``read(after:matching:)`` does, but stops at `end` — in whichever file now
    /// holds it, the live one or an archive it was rotated to — so a row written after
    /// `end` is left for the next, unbounded read. When `end` falls inside a line still
    /// being written, the page stops before that line and its cursor says so.
    ///
    /// - Parameters:
    ///   - cursor: Where to start, from ``cursor(since:through:)``.
    ///   - end: Where to stop: a cursor from ``endCursor()``.
    ///   - date: Rows stamped before it are dropped.
    ///   - matching: Which decoded rows to keep.
    /// - Returns: The rows in order and the cursor to resume from. When `end`'s file can no
    ///   longer be found, the read is not bounded.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file exists but cannot be read.
    func read<Row: JSONLinesRow>(
        after cursor: ActivityCursor,
        through end: ActivityCursor,
        since date: Date,
        matching: (Row) -> Bool
    ) throws -> JSONLinesPage<Row> {
        let keep: (Row) -> Bool = { $0.time >= date && matching($0) }
        guard end.inode != 0 else {
            return JSONLinesPage(nextOffset: 0, restarted: false, cursor: .start)
        }
        for _ in 0 ..< Self.attempts {
            let files = everyFile()
            guard let last = files.lastIndex(where: { $0.inode == end.inode }) else { break }
            var first = 0
            var restarted = false
            if cursor.inode != 0 {
                if let index = files.firstIndex(where: { $0.inode == cursor.inode }), index <= last {
                    first = index
                } else {
                    restarted = true
                }
            }
            var merged = JSONLinesPage<Row>(nextOffset: 0, restarted: restarted)
            var raced = false
            for index in first ... last {
                let file = files[index]
                let offset = index == first && !restarted ? cursor.offset : 0
                let page = try readFile(at: file.url, from: offset, through: index == last ? end.offset : nil, matching: keep)
                if page.cursor?.inode != file.inode {
                    raced = true
                    break
                }
                merged.rows += page.rows
                merged.rowCursors += page.rowCursors
                merged.skippedLines += page.skippedLines
                merged.cursor = page.cursor
                merged.nextOffset = page.nextOffset
            }
            if !raced { return merged }
        }
        return try read(after: cursor, matching: keep)
    }

    /// How far out of time order two rows of one log can be: the gap between a writer
    /// stamping a row and taking the log's lock, behind another writer that stamped later
    /// and locked first. A few seconds covers any wait for the lock short of a stall.
    static let stampSlack: TimeInterval = 5

    // MARK: - Private

    /// What one file's backward walk found.
    private enum Walk {
        /// The offset just after the newest row stamped before the date.
        case found(UInt64)
        /// Every row the file holds is in the window.
        case none
        /// The path no longer names the file the walk was meant for.
        case replaced
    }

    /// The field a backward walk reads from each line: its stamp, without the rest.
    private struct Stamp: Decodable {
        var time: String
    }

    /// How many times a walk or a bounded read starts over after a rotation raced it.
    private static let attempts = 3

    /// How much a backward walk reads at a time.
    private static let walkChunk: UInt64 = 64 * 1024

    /// The archives, oldest first, then the live file, each with its inode.
    private func everyFile() -> [Archive] {
        var files = archives()
        if let live = FileSignature.read(at: fileURL.path) {
            files.append(Archive(url: fileURL, inode: live.inode))
        }
        return files
    }

    /// Walks one file backward for the newest row stamped before `date`.
    ///
    /// - Parameters:
    ///   - date: How old a row must be to end the walk: the window's start, less the slack.
    ///   - file: The file, and the inode it must still have.
    ///   - limit: Where to start walking back from; the file's end when `nil`. Bytes after
    ///     the last newline below it are a line still being written, and are not a row.
    /// - Returns: What the walk found.
    private func offsetAfterNewestRow(before date: Date, in file: Archive, below limit: UInt64?) throws -> Walk {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file.url)
        } catch {
            if !FileManager.default.fileExists(atPath: file.url.path) { return .replaced }
            throw PenFileError.cannotOpen(url: file.url, reason: PenFileError.oneLineReason(error))
        }
        defer { try? handle.close() }
        guard FileSignature.read(descriptor: handle.fileDescriptor)?.inode == file.inode else { return .replaced }

        let decoder = JSONDecoder()
        do {
            let size = try handle.seekToEnd()
            var end = min(limit ?? size, size)
            // The offset just past the newline that ends the line the walk is inside;
            // `nil` until the first newline below the limit, since bytes after it are a
            // line still being written.
            var lineEnd: UInt64?
            // That line's bytes above `end`: its tail, whose head is in the next chunk down.
            var carried = Data()
            while end > 0 {
                let start = end - min(Self.walkChunk, end)
                try handle.seek(toOffset: start)
                var chunk = try handle.read(upToCount: Int(end - start)) ?? Data()
                chunk.append(carried)
                var cursor = chunk.endIndex
                while let newline = chunk[chunk.startIndex ..< cursor].lastIndex(of: Self.newline) {
                    if let lineEnd, Self.isStamped(chunk[chunk.index(after: newline) ..< cursor], before: date, using: decoder) {
                        return .found(lineEnd)
                    }
                    lineEnd = start + UInt64(chunk.distance(from: chunk.startIndex, to: newline)) + 1
                    cursor = newline
                }
                let head = chunk[chunk.startIndex ..< cursor]
                if start == 0 {
                    if let lineEnd, Self.isStamped(head, before: date, using: decoder) {
                        return .found(lineEnd)
                    }
                    return .none
                }
                carried = lineEnd == nil ? Data() : Data(head)
                end = start
            }
        } catch let error as PenFileError {
            throw error
        } catch {
            throw PenFileError.cannotOpen(url: file.url, reason: PenFileError.oneLineReason(error))
        }
        return .none
    }

    /// Whether a line carries a stamp, and it is before `date`. A line with none — empty,
    /// or a scrap a crash left — is stepped over, as a forward read steps over it.
    private static func isStamped(_ line: Data, before date: Date, using decoder: JSONDecoder) -> Bool {
        guard !line.isEmpty, let stamp = try? decoder.decode(Stamp.self, from: line),
              let time = try? Date(stamp.time, strategy: ActivityEvent.timeFormat)
        else { return false }
        return ActivityEvent.roundedToMilliseconds(time) < date
    }
}
