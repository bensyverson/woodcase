//
//  PenBundle+History.swift
//  Woodcase
//

import Foundation

public extension PenBundle {
    /// The writers' files in a bundle's `history/`, live and archived, sorted by name:
    /// what a copy that carries the bundle's history takes.
    ///
    /// A writer's file is named for its writer (`ana@mac.jsonl`, or an archive's
    /// `ana@mac.20260829T163104Z.jsonl`; <doc:WoodcaseActivityLog>). Anything else in
    /// `history/` — a hidden file, a legacy `activity.jsonl`, a sync service's
    /// conflicted copy (`ana@mac 2.jsonl`) — is no writer's, and readers skip it, so a
    /// copy leaves it behind. ``copy(_:to:history:)`` and ``export(_:to:identity:history:)``
    /// copy these files; an app that writes its own copy of a bundle — one whose document
    /// comes from memory rather than from disk — lists them here, or copies them with
    /// ``copyHistory(from:into:)``.
    ///
    /// - Parameter bundle: The bundle.
    /// - Returns: The files; empty when `history/` is missing or holds no writer's file.
    static func historyFiles(in bundle: URL) -> [URL] {
        guard let directory = PenLocation(bundle).historyDirectory else { return [] }
        return HistoryFiles(directory: directory, rotationThreshold: ActivityLog.rotationThreshold)
            .fileNames().map { directory.appendingPathComponent($0.name) }
    }

    /// Copies a bundle's writers' history files (``historyFiles(in:)``) into a `history/`
    /// directory, which is created if missing. Nothing is overwritten: a file already at a
    /// name fails the copy, so a caller that may meet one checks first.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to copy from.
    ///   - directory: The `history/` directory to copy into — a new bundle's
    ///     ``PenLocation/historyDirectory``, or an exported folder's `history/`.
    /// - Returns: How many files were copied.
    /// - Throws: ``PenFileError/writeFailed(url:reason:)`` when a file cannot be copied.
    @discardableResult
    static func copyHistory(from bundle: URL, into directory: URL) throws -> Int {
        let files = historyFiles(in: bundle)
        guard !files.isEmpty else { return 0 }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for file in files {
                try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent(file.lastPathComponent))
            }
        } catch {
            throw PenFileError.writeFailed(url: directory, reason: PenFileError.oneLineReason(error))
        }
        return files.count
    }
}

extension PenBundle {
    /// The first history file that copying a bundle's history into `directory` would
    /// overwrite.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to copy from.
    ///   - directory: The `history/` directory to copy into.
    /// - Returns: The file already there, or `nil` when none collides.
    static func collidingHistoryFile(from bundle: URL, into directory: URL) -> URL? {
        historyFiles(in: bundle)
            .map { directory.appendingPathComponent($0.lastPathComponent) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
