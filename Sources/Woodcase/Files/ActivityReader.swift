//
//  ActivityReader.swift
//  Woodcase
//

import Foundation

/// Reads an ``ActivityLog`` forward from a byte offset, so a follower never sees the
/// same event twice.
///
/// The reader is the other half of the log's contract with the viewer and the CLI. It
/// decodes whole lines only, filters by file and identity, and hands back the offset to
/// resume from:
///
/// ```swift
/// let reader = ActivityReader(log: ActivityLogLocation.log(for: url))
/// var page = try reader.read(file: url)
/// for event in page.events { show(event) }
/// // later …
/// page = try reader.read(from: page.nextOffset, file: url)
/// ```
///
/// ## No lock, on purpose
///
/// A writer appends whole lines under an exclusive lock, but a reader takes no lock at
/// all: it stops at the last newline in the file, so a line a writer is halfway through
/// is simply not consumed yet, and the next read picks it up complete. That makes
/// following the log free of any contention with the process doing the editing.
///
/// ## Rotation
///
/// ``ActivityLog`` renames the live file aside when it grows past its threshold. A
/// follower notices because the file it resumes into is *shorter* than the offset it
/// held; the reader then starts from zero and sets ``Page/restarted``. The heuristic
/// fails only if a fresh log grows past the old offset between two polls — megabytes
/// within one poll interval — so a follower that keeps up never misses a rotation.
public struct ActivityReader: Friendly {
    /// Reads the given log.
    ///
    /// - Parameter log: The log to read. There is no default: which log to read depends
    ///   on which .pen file (or which directory) the caller means, and
    ///   ``ActivityLogLocation`` is where that is decided.
    public init(log: ActivityLog) {
        self.log = log
    }

    /// The log being read.
    public let log: ActivityLog

    /// What one read produced, and where to resume.
    public struct Page: Friendly {
        /// Creates a page.
        ///
        /// - Parameters:
        ///   - events: The events read, after filtering, in log order.
        ///   - nextOffset: The byte offset to resume from.
        ///   - restarted: Whether the log had been rotated since the last read.
        ///   - skippedLines: How many lines could not be decoded.
        public init(events: [ActivityEvent], nextOffset: UInt64, restarted: Bool, skippedLines: Int) {
            self.events = events
            self.nextOffset = nextOffset
            self.restarted = restarted
            self.skippedLines = skippedLines
        }

        /// The events read, after filtering, in the order they were appended.
        public var events: [ActivityEvent]

        /// The offset just past the last complete line, to pass to the next read.
        ///
        /// It counts every complete line the read covered, filtered out or not, so a
        /// filtered follower still advances past events it does not care about.
        public var nextOffset: UInt64

        /// Whether the log was rotated and this read started over from its beginning.
        ///
        /// A follower that shows a continuous feed should treat this as "the history
        /// before here has moved to an archive file", not as new activity.
        public var restarted: Bool

        /// How many complete lines could not be decoded as events.
        ///
        /// A line written by a newer, incompatible version — or a scrap left by a
        /// crash — is counted here and stepped over rather than stopping the reader
        /// forever at the same byte.
        public var skippedLines: Int
    }

    /// Reads every complete line from `offset` on.
    ///
    /// - Parameters:
    ///   - offset: Where to start, from a previous ``Page/nextOffset``. Zero reads the
    ///     whole live log.
    ///   - file: Show only events for this .pen file. Compared as
    ///     ``ActivityEvent/canonicalPath(for:)``, so any spelling of the path matches.
    ///   - identity: Show only events written by this `--as` name.
    /// - Returns: The matching events and the offset to resume from. A log that does not
    ///   exist yet reads as an empty page rather than an error — nothing has been
    ///   logged, which is not a failure.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the log exists but cannot
    ///   be read.
    public func read(
        from offset: UInt64 = 0,
        file: URL? = nil,
        identity: String? = nil
    ) throws -> Page {
        let url = log.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Page(events: [], nextOffset: 0, restarted: offset > 0, skippedLines: 0)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }
        defer { try? handle.close() }

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

        let wanted = file.map(ActivityEvent.canonicalPath(for:))
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
        }

        page.nextOffset = start + UInt64(consumed)
        return page
    }

    /// The last `count` matching events in the live log.
    ///
    /// - Parameters:
    ///   - count: How many events to return. The whole log if it holds fewer.
    ///   - file: Show only events for this .pen file.
    ///   - identity: Show only events written by this `--as` name.
    /// - Returns: The most recent matching events, oldest first.
    /// - Throws: Whatever ``read(from:file:identity:)`` throws.
    public func tail(count: Int, file: URL? = nil, identity: String? = nil) throws -> [ActivityEvent] {
        guard count > 0 else { return [] }
        let page = try read(file: file, identity: identity)
        return Array(page.events.suffix(count))
    }

    /// The newest event recorded for one file, read from the end of the log.
    ///
    /// The one question a *writer* asks the log — "is the file still where the log left
    /// it?" — and the answer is always in the last few lines. Reading forward to find it
    /// would decode the whole history on every write, so this walks backwards in chunks
    /// and decodes only as far as it must: one chunk for the ordinary case, more only
    /// when the newest lines belong to other files.
    ///
    /// - Parameter file: The .pen file to look for. `nil` takes the newest event of any
    ///   file, which is what a caller with a single-file log wants.
    /// - Returns: The newest matching event, or `nil` when the log holds none — a log
    ///   that does not exist yet included, because nothing has been recorded, which is
    ///   not a failure.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if the log exists but cannot
    ///   be read.
    public func newest(file: URL? = nil) throws -> ActivityEvent? {
        let url = log.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw PenFileError.cannotOpen(url: url, reason: PenFileError.oneLineReason(error))
        }
        defer { try? handle.close() }

        let wanted = file.map(ActivityEvent.canonicalPath(for:))
        let decoder = JSONDecoder()
        do {
            var end = try handle.seekToEnd()
            // Bytes from the chunk below that turned out to be the head of a line
            // this chunk had only the tail of.
            var carried = Data()
            while end > 0 {
                let size = min(Self.reverseChunk, end)
                let start = end - size
                try handle.seek(toOffset: start)
                var chunk = try handle.read(upToCount: Int(size)) ?? Data()
                chunk.append(carried)
                var lines = chunk.split(separator: Self.newline, omittingEmptySubsequences: false)
                // The first segment is only a whole line when the read reached the
                // log's beginning; otherwise it continues into the chunk below.
                carried = start > 0 ? Data(lines.removeFirst()) : Data()
                for line in lines.reversed() where !line.isEmpty {
                    guard let event = try? ActivityEvent(line: Data(line), using: decoder) else {
                        continue
                    }
                    if let wanted, event.file != wanted { continue }
                    return event
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

    /// The byte that ends every line.
    private static let newline: UInt8 = 0x0A

    /// How much of the log ``newest(file:)`` reads at a time, walking backwards.
    ///
    /// A whole event line is a few hundred bytes, so one chunk holds hundreds of them:
    /// the backwards walk almost always ends in its first read.
    private static let reverseChunk: UInt64 = 64 * 1024
}
