//
//  HistoryFiles.swift
//  Woodcase
//

import Foundation

/// A bundle's shared history on disk: one ``JSONLinesFile`` per ``HistoryWriter`` in one
/// directory, read as one log merged by time.
///
/// Each writer's file is an ordinary rotating lines file — `ben@grace.jsonl`, archived as
/// `ben@grace.<stamp>.jsonl` — so appending, locking and rotation are exactly a bare
/// file's log's. What this type adds is reading them together:
///
/// - **Merged by time.** Each read gathers every writer's new rows and merges them by
///   each file's next row: the row with the earliest ``JSONLinesRow/time`` goes first,
///   and a tie goes to the writer whose name sorts first. A writer's own rows are never
///   reordered — a clock that stepped back on one device does not shuffle that device's
///   history — and the same files always merge to the same order.
/// - **One position per writer.** Positions are ``ActivityCursor``s with
///   ``ActivityCursor/writers``; a writer missing from one is read from its first row, so
///   a file a sync delivers late is never skipped, even when its rows are older than
///   what was already read.
///
/// A file in the directory whose name is not a writer's — a legacy `activity.jsonl`, a
/// sync service's conflicted copy — is not read.
struct HistoryFiles: Friendly {
    /// The history directory: a bundle's `history/`.
    let directory: URL

    /// The size at which a writer's live file is moved aside before the next append.
    let rotationThreshold: UInt64

    /// The file a writer appends to.
    ///
    /// - Parameter writer: The writer.
    /// - Returns: Its lines file.
    func file(for writer: HistoryWriter) -> JSONLinesFile {
        file(stem: writer.rawValue)
    }

    /// Every writer with a file here, live or archived, sorted by name: the order a tie
    /// in time is broken in.
    ///
    /// - Returns: Each writer's ``HistoryWriter/rawValue``; empty when the directory is
    ///   missing.
    func writers() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let stems = names.compactMap { name -> String? in
            guard name.hasSuffix(Self.fileExtension),
                  let stem = name.split(separator: ".", maxSplits: 1).first.map(String.init),
                  HistoryWriter(fileStem: stem) != nil
            else { return nil }
            return stem
        }
        return Set(stems).sorted()
    }

    /// Reads every writer's rows after a position, merged.
    ///
    /// - Parameters:
    ///   - cursor: Where the last read ended. ``ActivityCursor/start`` reads everything; a
    ///     one-file cursor that is not the start — from some other log — reads everything
    ///     and says ``JSONLinesPage/restarted``.
    ///   - matching: Which decoded rows to keep.
    /// - Returns: The merged rows, each with the position just after it, and the position
    ///   after every writer's last complete line.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file exists but cannot be read.
    func read<Row: JSONLinesRow>(after cursor: ActivityCursor, matching: (Row) -> Bool) throws -> JSONLinesPage<Row> {
        let (start, foreign) = Self.positions(of: cursor)
        var pages: [(writer: String, page: JSONLinesPage<Row>)] = []
        for writer in writers() {
            let page = try file(stem: writer).read(after: start[writer] ?? .start, matching: matching)
            pages.append((writer, page))
        }
        return Self.merge(pages, from: start, restarted: foreign)
    }

    /// Reads the rows after `cursor` up to `end`, keeping those stamped at or after
    /// `date`: each writer's file as ``JSONLinesFile/read(after:through:since:matching:)``
    /// reads it, merged. A writer `end` does not name had no rows when it was taken, so
    /// it is left for the next, unbounded read.
    ///
    /// - Parameters:
    ///   - cursor: Where to start, from ``cursor(since:through:)``.
    ///   - end: Where to stop, from ``endCursor()``.
    ///   - date: Rows stamped before it are dropped.
    ///   - matching: Which decoded rows to keep.
    /// - Returns: The merged rows, and the position to resume from.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file exists but cannot be read.
    func read<Row: JSONLinesRow>(
        after cursor: ActivityCursor,
        through end: ActivityCursor,
        since date: Date,
        matching: (Row) -> Bool
    ) throws -> JSONLinesPage<Row> {
        let (start, foreign) = Self.positions(of: cursor)
        var pages: [(writer: String, page: JSONLinesPage<Row>)] = []
        for (writer, stop) in end.writers.sorted(by: { $0.key < $1.key }) {
            let page = try file(stem: writer).read(after: start[writer] ?? .start, through: stop, since: date, matching: matching)
            pages.append((writer, page))
        }
        return Self.merge(pages, from: start, restarted: foreign)
    }

    /// Where each writer's rows at or after `date` begin, walking back from `end`: see
    /// ``JSONLinesFile/cursor(since:through:)``.
    ///
    /// - Parameters:
    ///   - date: The oldest moment in the window.
    ///   - end: Where the window ends, from ``endCursor()``.
    /// - Returns: One position per writer `end` names.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file the walk needs cannot
    ///   be read.
    func cursor(since date: Date, through end: ActivityCursor) throws -> ActivityCursor {
        var positions: [String: ActivityCursor] = [:]
        for (writer, stop) in end.writers {
            positions[writer] = try file(stem: writer).cursor(since: date, through: stop)
        }
        return ActivityCursor(writers: positions)
    }

    /// The position at the end of every writer's last whole line as it is now.
    ///
    /// - Returns: One position per writer; ``ActivityCursor/start`` when there are none.
    func endCursor() -> ActivityCursor {
        var positions: [String: ActivityCursor] = [:]
        for writer in writers() {
            let end = file(stem: writer).endCursor()
            if end != .start { positions[writer] = end }
        }
        return ActivityCursor(writers: positions)
    }

    /// The position at the start of every writer's **live** file: what a read of the live
    /// files alone, without the archives, starts from.
    ///
    /// - Returns: One position per writer with a live file.
    func liveStart() -> ActivityCursor {
        var positions: [String: ActivityCursor] = [:]
        for writer in writers() {
            if let inode = FileSignature.read(at: file(stem: writer).fileURL.path)?.inode {
                positions[writer] = ActivityCursor(inode: inode, offset: 0)
            }
        }
        return ActivityCursor(writers: positions)
    }

    /// The newest matching row of each writer's live file, in writer order.
    ///
    /// - Parameter matching: Which decoded rows count.
    /// - Returns: At most one row per writer.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file exists but cannot be read.
    func newestPerWriter<Row: JSONLinesRow>(matching: (Row) -> Bool) throws -> [Row] {
        try writers().compactMap { try file(stem: $0).newest(matching: matching) }
    }

    /// The newest matching row of any writer: the one the merge would put last.
    ///
    /// - Parameter matching: Which decoded rows count.
    /// - Returns: The row, or `nil` when no writer has one.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` if a file exists but cannot be read.
    func newest<Row: JSONLinesRow>(matching: (Row) -> Bool) throws -> Row? {
        try newestPerWriter(matching: matching).reduce(nil) { newest, row in
            guard let newest, newest.time > row.time else { return row }
            return newest
        }
    }

    // MARK: - Private

    /// A writer's file's extension.
    private static let fileExtension = ".jsonl"

    /// The file a writer's rows are in.
    private func file(stem: String) -> JSONLinesFile {
        JSONLinesFile(home: directory, stem: stem, rotationThreshold: rotationThreshold)
    }

    /// A cursor's per-writer positions, and whether it was a one-file cursor from some
    /// other log, which says nothing about these files.
    private static func positions(of cursor: ActivityCursor) -> ([String: ActivityCursor], foreign: Bool) {
        (cursor.writers, cursor.writers.isEmpty && cursor != .start)
    }

    /// Merges each writer's page by each page's next row: earliest time first, a tie to
    /// the writer listed first.
    ///
    /// - Parameters:
    ///   - pages: Each writer's page, in writer order.
    ///   - start: The positions the read began at.
    ///   - restarted: Whether the read could not follow its cursor.
    /// - Returns: The merged page, its row cursors and its end in per-writer form.
    private static func merge<Row: JSONLinesRow>(
        _ pages: [(writer: String, page: JSONLinesPage<Row>)],
        from start: [String: ActivityCursor],
        restarted: Bool
    ) -> JSONLinesPage<Row> {
        var positions = start
        var merged = JSONLinesPage<Row>(nextOffset: 0, restarted: restarted || pages.contains { $0.page.restarted })
        var heads = Array(repeating: 0, count: pages.count)
        while true {
            var next: Int?
            for index in pages.indices where heads[index] < pages[index].page.rows.count {
                guard let current = next else {
                    next = index
                    continue
                }
                if pages[index].page.rows[heads[index]].time < pages[current].page.rows[heads[current]].time {
                    next = index
                }
            }
            guard let index = next else { break }
            let (writer, page) = pages[index]
            merged.rows.append(page.rows[heads[index]])
            positions[writer] = page.rowCursors[heads[index]]
            merged.rowCursors.append(ActivityCursor(writers: positions))
            heads[index] += 1
        }
        for (writer, page) in pages {
            if let end = page.cursor, end != .start { positions[writer] = end }
            merged.skippedLines += page.skippedLines
        }
        merged.cursor = ActivityCursor(writers: positions)
        return merged
    }
}
