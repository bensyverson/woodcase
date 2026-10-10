//
//  JSONLinesFile.swift
//  Woodcase
//

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// An append-only file of JSON lines that rotates itself: the storage under both
/// ``ActivityLog`` (`activity.jsonl`) and ``ViewLog`` (`views.jsonl`).
///
/// It owns the three things the two logs must do identically — whole-batch appends under
/// an exclusive `flock(2)`, rotation past a size threshold to `<stem>.<timestamp>.jsonl`,
/// and finding those archives again by inode — and knows nothing about what a line says.
/// Each log keeps its own stem, so each rotates on its own and neither's archives are
/// mistaken for the other's.
struct JSONLinesFile: Friendly {
    /// Creates a handle on a file; nothing is touched until the first append.
    ///
    /// - Parameters:
    ///   - home: The directory the file lives in.
    ///   - stem: The name before `.jsonl`: `activity` or `views`.
    ///   - rotationThreshold: The size at which the live file is moved aside before the
    ///     next append.
    init(home: URL, stem: String, rotationThreshold: UInt64) {
        self.home = home
        self.stem = stem
        self.rotationThreshold = rotationThreshold
    }

    /// The directory the file lives in.
    let home: URL

    /// The name before `.jsonl`.
    let stem: String

    /// The size at which the live file is moved aside before the next append.
    let rotationThreshold: UInt64

    /// The live file's name: `<stem>.jsonl`.
    var fileName: String {
        "\(stem).jsonl"
    }

    /// The live file.
    var fileURL: URL {
        home.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Appends whole lines, rotating first when the file is past the threshold.
    ///
    /// - Parameters:
    ///   - payload: Complete lines, each ending in a newline.
    ///   - timeout: How long to wait for another process to release the lock.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)``,
    ///   ``PenFileError/writeFailed(url:reason:)`` or ``PenFileError/lockTimeout(url:timeout:)``,
    ///   each naming the file.
    func append(_ payload: Data, timeout: Duration) async throws {
        var attempt = 1
        while true {
            let mayRetry = attempt < Self.maximumAttempts
            if try await appendOnce(payload, timeout: timeout, mayRetry: mayRetry) { return }
            attempt += 1
        }
    }

    /// The name a file rotated at `date` is moved to: `<stem>.20260829T163104Z.jsonl`.
    ///
    /// - Parameter date: When the rotation happened.
    /// - Returns: The archive's URL, beside the live file.
    func archiveURL(rotatedAt date: Date) -> URL {
        let stamp = date.formatted(Self.archiveTimeFormat)
        return home.appendingPathComponent("\(stem).\(stamp).jsonl", isDirectory: false)
    }

    /// A rotated file and the inode it kept through the rename.
    struct Archive: Friendly {
        /// The archive file.
        var url: URL
        /// Its inode — the one a cursor taken before the rotation names.
        var inode: UInt64
    }

    /// The rotated files beside the live one, oldest first.
    ///
    /// Ordered by the timestamp in the name, then by the collision suffix
    /// (`…Z.jsonl` before `…Z-1.jsonl`), which is the order they were rotated in.
    ///
    /// - Returns: Every archive; empty when the directory is missing or holds none.
    func archives() -> [Archive] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        let prefix = "\(stem)."
        let suffix = ".jsonl"
        let ranked: [(key: (stamp: String, number: Int), archive: Archive)] = names.compactMap { name in
            guard name != fileName, name.hasPrefix(prefix), name.hasSuffix(suffix),
                  name.count > prefix.count + suffix.count
            else { return nil }
            let middle = String(name.dropFirst(prefix.count).dropLast(suffix.count))
            let parts = middle.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let number = parts.count == 2 ? (Int(parts[1]) ?? Int.max) : 0
            let url = home.appendingPathComponent(name, isDirectory: false)
            guard let inode = FileSignature.read(at: url.path)?.inode else { return nil }
            return ((String(parts[0]), number), Archive(url: url, inode: inode))
        }
        return ranked
            .sorted { ($0.key.stamp, $0.key.number) < ($1.key.stamp, $1.key.number) }
            .map(\.archive)
    }

    /// The byte that ends every line.
    static let newline: UInt8 = 0x0A

    // MARK: - Private

    /// How many times an append re-takes the lock before giving up on rotation.
    ///
    /// One rotation costs one retry; the extra attempts absorb the instant in which a
    /// competing process has renamed the file but not yet recreated it.
    private static let maximumAttempts = 4

    /// The timestamp format in a rotated file's name: ISO-8601 basic, UTC, no
    /// separators, because a `:` in a file name is awkward everywhere.
    private static let archiveTimeFormat = Date.ISO8601FormatStyle(
        dateSeparator: .omitted,
        timeSeparator: .omitted,
        includingFractionalSeconds: false
    )

    /// One attempt at appending.
    ///
    /// - Returns: `true` when the payload was written, `false` when the file was rotated
    ///   or vanished under us and the caller should try again.
    private func appendOnce(_ payload: Data, timeout: Duration, mayRetry: Bool) async throws -> Bool {
        try createFileIfNeeded()

        let lock: FileLock
        do {
            lock = try await FileLock.acquire(fileURL, mode: .exclusive, timeout: timeout)
        } catch let error as PenFileError {
            // Another process may have renamed the file a moment ago and not yet
            // recreated it. That is a retry, not a failure.
            if case .cannotOpen = error, mayRetry { return false }
            throw error
        }
        defer { lock.release() }

        if try Self.size(of: lock) >= rotationThreshold, mayRetry {
            try rotate()
            return false
        }
        try Self.appendBytes(payload, to: lock)
        return true
    }

    /// Creates the file if it is not there yet, never truncating an existing one.
    private func createFileIfNeeded() throws {
        let descriptor = open(fileURL.path, O_WRONLY | O_CREAT, mode_t(0o644))
        guard descriptor >= 0 else {
            throw PenFileError.cannotOpen(url: fileURL, reason: FileLock.systemMessage(errno))
        }
        close(descriptor)
    }

    /// Moves the file aside and puts an empty one in its place.
    ///
    /// Only ever called while this process holds the file's exclusive lock, so no other
    /// participant can be mid-append when the path changes underneath it.
    private func rotate() throws {
        let archive = uniqueArchiveURL()
        guard rename(fileURL.path, archive.path) == 0 else {
            throw PenFileError.writeFailed(url: fileURL, reason: FileLock.systemMessage(errno))
        }
        try createFileIfNeeded()
    }

    /// An archive name nothing else has taken, so two rotations in one second do not
    /// overwrite each other.
    private func uniqueArchiveURL() -> URL {
        let base = archiveURL(rotatedAt: Date())
        guard FileManager.default.fileExists(atPath: base.path) else { return base }
        let name = base.deletingPathExtension().lastPathComponent
        for suffix in 1 ... 999 {
            let candidate = home.appendingPathComponent("\(name)-\(suffix).jsonl", isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return home.appendingPathComponent("\(name)-\(UUID().uuidString).jsonl", isDirectory: false)
    }

    /// The locked file's size in bytes.
    private static func size(of lock: FileLock) throws -> UInt64 {
        var status = stat()
        guard fstat(lock.descriptor, &status) == 0 else {
            throw PenFileError.cannotOpen(url: lock.url, reason: FileLock.systemMessage(errno))
        }
        return UInt64(max(0, status.st_size))
    }

    /// Writes the whole payload at the end of the locked file and flushes it.
    private static func appendBytes(_ payload: Data, to lock: FileLock) throws {
        guard lseek(lock.descriptor, 0, SEEK_END) >= 0 else {
            throw PenFileError.writeFailed(url: lock.url, reason: FileLock.systemMessage(errno))
        }
        var remaining = payload[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { buffer in
                Self.writeBytes(lock.descriptor, buffer.baseAddress, buffer.count)
            }
            if written > 0 {
                remaining = remaining.dropFirst(written)
            } else if written < 0, errno == EINTR {
                continue
            } else {
                throw PenFileError.writeFailed(url: lock.url, reason: FileLock.systemMessage(errno))
            }
        }
        fsync(lock.descriptor)
    }

    /// A named wrapper around POSIX `write`, so the call site is unambiguous.
    private static func writeBytes(_ descriptor: Int32, _ bytes: UnsafeRawPointer?, _ count: Int) -> Int {
        write(descriptor, bytes, count)
    }
}
