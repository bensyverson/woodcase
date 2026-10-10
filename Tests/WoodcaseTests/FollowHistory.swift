//
//  FollowHistory.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Writes a log's history straight to disk — rotated archives, oldest first, then the
/// live file — the shape ``ActivityLog`` and ``ViewLog`` leave after rotating, without
/// appending megabytes through the lock to get there.
enum FollowHistory {
    /// Writes one log's files.
    ///
    /// - Parameters:
    ///   - files: Each file's lines, without newlines: every archive oldest first, then
    ///     the live file last.
    ///   - lines: The log's storage, whose home and stem name the files.
    /// - Throws: Anything writing the files throws.
    static func write(_ files: [[Data]], to lines: JSONLinesFile) throws {
        try FileManager.default.createDirectory(at: lines.home, withIntermediateDirectories: true)
        for (index, rows) in files.enumerated() {
            let url = index == files.count - 1
                ? lines.fileURL
                : lines.home.appendingPathComponent("\(lines.stem).2026010\(index)T000000Z.jsonl")
            var payload = Data()
            for row in rows {
                payload.append(row)
                payload.append(JSONLinesFile.newline)
            }
            try payload.write(to: url)
        }
    }

    /// Writes an activity log's files.
    ///
    /// - Parameters:
    ///   - files: Each file's rows: every archive oldest first, then the live file last.
    ///   - log: The log to write.
    /// - Throws: Anything encoding or writing throws.
    static func write(_ files: [[ActivityEvent]], to log: ActivityLog) throws {
        let encoder = ActivityEvent.makeEncoder()
        try write(files.map { try $0.map { try $0.jsonLine(using: encoder) } }, to: log.lines)
    }

    /// Writes a view log's files.
    ///
    /// - Parameters:
    ///   - files: Each file's views: every archive oldest first, then the live file last.
    ///   - log: The log to write.
    /// - Throws: Anything encoding or writing throws.
    static func write(_ files: [[ViewEvent]], to log: ViewLog) throws {
        try write(files.map { try $0.map { try $0.jsonLine() } }, to: log.lines)
    }
}
