//
//  ActivityLog+Archives.swift
//  Woodcase
//

import Foundation

extension ActivityLog {
    /// A rotated log file and the inode it kept through the rename.
    struct Archive: Friendly {
        /// The archive file.
        var url: URL
        /// Its inode — the one a cursor taken before the rotation names.
        var inode: UInt64
    }

    /// The rotated logs beside the live one, oldest first.
    ///
    /// Ordered by the timestamp in the name, then by the collision suffix
    /// ``archiveURL(rotatedAt:)`` callers append (`…Z.jsonl` before `…Z-1.jsonl`), which is
    /// the order they were rotated in.
    ///
    /// - Returns: Every archive; empty when the directory is missing or holds none.
    func archives() -> [Archive] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        let prefix = "activity."
        let suffix = ".jsonl"
        let ranked: [(key: (stamp: String, number: Int), archive: Archive)] = names.compactMap { name in
            guard name != Self.fileName, name.hasPrefix(prefix), name.hasSuffix(suffix),
                  name.count > prefix.count + suffix.count
            else { return nil }
            let stem = String(name.dropFirst(prefix.count).dropLast(suffix.count))
            let parts = stem.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let number = parts.count == 2 ? (Int(parts[1]) ?? Int.max) : 0
            let url = home.appendingPathComponent(name, isDirectory: false)
            guard let inode = FileSignature.read(at: url.path)?.inode else { return nil }
            return ((String(parts[0]), number), Archive(url: url, inode: inode))
        }
        return ranked
            .sorted { ($0.key.stamp, $0.key.number) < ($1.key.stamp, $1.key.number) }
            .map(\.archive)
    }
}
