//
//  PenBundle+History.swift
//  Woodcase
//

import Foundation

extension PenBundle {
    /// The writers' files in a bundle's `history/`, live and archived, by name.
    ///
    /// - Parameter bundle: The bundle.
    /// - Returns: The file names; empty when `history/` is missing.
    static func historyFileNames(in bundle: URL) -> [String] {
        guard let directory = PenLocation(bundle).historyDirectory else { return [] }
        return HistoryFiles(directory: directory, rotationThreshold: ActivityLog.rotationThreshold)
            .fileNames().map(\.name)
    }

    /// Copies a bundle's writers' history files into a `history/` directory, which is
    /// created if missing. Nothing is overwritten: the caller checks first
    /// (``collidingHistoryFile(from:into:)``).
    ///
    /// - Parameters:
    ///   - bundle: The bundle to copy from.
    ///   - directory: The `history/` directory to copy into.
    /// - Returns: How many files were copied.
    /// - Throws: ``PenFileError/writeFailed(url:reason:)`` when a file cannot be copied.
    static func copyHistory(from bundle: URL, into directory: URL) throws -> Int {
        let names = historyFileNames(in: bundle)
        guard !names.isEmpty, let source = PenLocation(bundle).historyDirectory else { return 0 }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in names {
                try FileManager.default.copyItem(
                    at: source.appendingPathComponent(name), to: directory.appendingPathComponent(name)
                )
            }
        } catch {
            throw PenFileError.writeFailed(url: directory, reason: PenFileError.oneLineReason(error))
        }
        return names.count
    }

    /// The first history file that copying a bundle's history into `directory` would
    /// overwrite.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to copy from.
    ///   - directory: The `history/` directory to copy into.
    /// - Returns: The file already there, or `nil` when none collides.
    static func collidingHistoryFile(from bundle: URL, into directory: URL) -> URL? {
        historyFileNames(in: bundle)
            .map { directory.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
