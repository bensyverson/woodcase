//
//  ActivityLog.swift
//  Woodcase
//

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The append-only JSONL file every committed edit is written to.
///
/// One ``ActivityEvent`` per line, in the order the operations were applied. The log is
/// the cheapest durable state this package keeps: it is the history, the feed the viewer
/// tails, and the source `woodcase undo` replays. Nothing reads it to reconstruct a
/// document — the .pen file is the truth — so a lost log costs history, not data.
///
/// ## Where it lives
///
/// With the project, not with the user: `.woodcase/activity.jsonl` at the repository root
/// above the .pen file, or beside the file when there is no repository, or wherever
/// `$WOODCASE_HOME` says. ``ActivityLogLocation`` makes that choice and is the only place
/// that makes it; this type is handed the answer.
///
/// ```swift
/// let log = ActivityLogLocation.log(for: url)   // <repo>/.woodcase/activity.jsonl
/// try await log.append(recorder.events)
/// ```
///
/// The directory is created on the first append, and — when it is a repository's —
/// ignored by that repository at the same moment. Tests inject a temporary directory with
/// ``init(home:origin:)`` rather than mutating the process environment.
///
/// ## Two processes, no torn lines
///
/// An append takes an exclusive `flock(2)` on the log file — the same lock a
/// ``PenFileTransaction`` takes on a .pen file — and writes every line of the batch in
/// one pass at the end of the file. Two `woodcase` processes appending at the same
/// instant therefore produce whole, separate lines rather than one interleaved mess.
/// Readers do not take the lock: ``ActivityReader`` never consumes a line that has no
/// newline yet, which is the same guarantee at a fraction of the cost.
///
/// ## Rotation
///
/// Before appending, a log already at or past ``rotationThreshold`` is renamed to
/// `activity.<timestamp>.jsonl` beside itself and a fresh empty file takes its place, so
/// the live file never grows without bound. The rename happens under the lock, so only
/// one process rotates a given file. A follower notices because the file it resumes into
/// is shorter than its offset — see ``ActivityReader/Page/restarted``.
public struct ActivityLog: Friendly {
    /// Uses an explicit directory, whatever the environment says.
    ///
    /// - Parameters:
    ///   - home: The directory the log lives in. Created on first append.
    ///   - origin: Why it is that directory. The default, ``Origin/directory``, is the
    ///     answer for a caller that chose the path itself — a test, an editor — and
    ///     leaves no `.gitignore` line behind.
    public init(home: URL, origin: Origin = .directory) {
        self.home = home
        self.origin = origin
    }

    /// The environment variable that moves the log's directory.
    ///
    /// One name, defined by ``WoodcaseHome/environmentVariable``: it moves the caches too.
    public static let homeEnvironmentVariable = WoodcaseHome.environmentVariable

    /// The directory, at a repository root or beside a .pen file, that holds the log.
    ///
    /// The same name ``WoodcaseHome`` uses in a user's home directory.
    public static let directoryName = WoodcaseHome.directoryName

    /// The `.gitignore` line that keeps a repository's log out of its history.
    public static let ignorePattern = "\(directoryName)/"

    /// The comment written above ``ignorePattern`` when it is added to a `.gitignore`.
    public static let ignoreComment =
        "Woodcase activity log (local history of .pen edits; the .pen files are the truth)"

    /// The log's file name inside ``home``.
    public static let fileName = "activity.jsonl"

    /// The size at which the live log is moved aside before the next append.
    public static let rotationThreshold: UInt64 = 8 * 1024 * 1024

    /// How long an append waits for another process to release the log's lock.
    public static let defaultTimeout: Duration = .seconds(5)

    /// The directory the log lives in.
    public let home: URL

    /// Why the log is in ``home`` — what ``ActivityLogLocation`` decided.
    public let origin: Origin

    /// The live log file.
    public var fileURL: URL {
        home.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Appends events to the log, creating the directory and file if needed.
    ///
    /// Every line is written in one pass under an exclusive lock, so a batch is never
    /// split by another writer. An empty batch does nothing at all — it does not even
    /// create the file.
    ///
    /// - Parameters:
    ///   - events: The events to append, in the order they were applied.
    ///   - timeout: How long to wait for another process to release the log's lock.
    /// - Throws: ``PenFileError/writeFailed(url:reason:)`` if the directory or the line
    ///   cannot be written, ``PenFileError/cannotOpen(url:reason:)`` if the log cannot be
    ///   opened, or ``PenFileError/lockTimeout(url:timeout:)`` if another process holds
    ///   the lock past `timeout`. Every case names the log file, not the .pen file.
    public func append(_ events: [ActivityEvent], timeout: Duration = defaultTimeout) async throws {
        guard !events.isEmpty else { return }

        let encoder = ActivityEvent.makeEncoder()
        var payload = Data()
        for event in events {
            try payload.append(event.jsonLine(using: encoder))
            payload.append(Self.newline)
        }

        try createDirectoryIfNeeded()
        var attempt = 1
        while true {
            let mayRetry = attempt < Self.maximumAttempts
            if try await appendOnce(payload, timeout: timeout, mayRetry: mayRetry) { return }
            attempt += 1
        }
    }

    /// The name a log rotated at `date` is moved to: `activity.20260829T163104Z.jsonl`.
    ///
    /// The timestamp is ISO-8601 basic format in UTC — no separators, because a `:` in a
    /// file name is awkward on every platform that has ever had a Finder.
    ///
    /// - Parameter date: When the rotation happened.
    /// - Returns: The archive's URL, beside the live log.
    public func archiveURL(rotatedAt date: Date) -> URL {
        let stamp = date.formatted(Self.archiveTimeFormat)
        return home.appendingPathComponent("activity.\(stamp).jsonl", isDirectory: false)
    }

    // MARK: - Private

    /// How many times an append re-takes the lock before giving up on rotation.
    ///
    /// One rotation costs one retry; the extra attempts absorb the instant in which a
    /// competing process has renamed the log but not yet recreated it.
    private static let maximumAttempts = 4

    /// The byte that ends every line.
    private static let newline: UInt8 = 0x0A

    /// The timestamp format in a rotated log's name.
    private static let archiveTimeFormat = Date.ISO8601FormatStyle(
        dateSeparator: .omitted,
        timeSeparator: .omitted,
        includingFractionalSeconds: false
    )

    /// One attempt at appending.
    ///
    /// - Returns: `true` when the payload was written, `false` when the log was rotated
    ///   or vanished under us and the caller should try again.
    private func appendOnce(_ payload: Data, timeout: Duration, mayRetry: Bool) async throws -> Bool {
        try createFileIfNeeded()

        let lock: FileLock
        do {
            lock = try await FileLock.acquire(fileURL, mode: .exclusive, timeout: timeout)
        } catch let error as PenFileError {
            // Another process may have renamed the log a moment ago and not yet
            // recreated it. That is a retry, not a failure.
            if case .cannotOpen = error, mayRetry { return false }
            throw error
        }
        defer { lock.release() }

        if try Self.size(of: lock) >= Self.rotationThreshold, mayRetry {
            try rotate()
            return false
        }
        try Self.appendBytes(payload, to: lock)
        return true
    }

    /// Creates ``home`` if it is not there yet, and tells the repository to ignore it.
    private func createDirectoryIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: home.path) else { return }
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        } catch {
            throw PenFileError.writeFailed(url: fileURL, reason: PenFileError.oneLineReason(error))
        }
        ignoreInRepository()
    }

    /// Adds `.woodcase/` to the repository's `.gitignore`, once, when this log is a
    /// repository's.
    ///
    /// Best effort on purpose: the edit and its log line are the work, and a read-only
    /// `.gitignore` is not a reason to fail either of them. A repository that ignores the
    /// directory some other way simply never sees the line, because
    /// ``RepositoryIgnoreFile`` checks first.
    ///
    /// When it does change the file it says so, once, on standard error. Editing a
    /// tracked file the caller did not name is exactly the kind of side effect that has
    /// to be announced: the next `git status` or `git diff` shows a change nobody
    /// remembers making, and an agent that cannot account for it has to go looking.
    /// Standard output stays the verb's answer.
    private func ignoreInRepository() {
        guard case let .repository(root) = origin else { return }
        let ignoreFile = RepositoryIgnoreFile(root: root)
        guard (try? ignoreFile.addIfMissing(Self.ignorePattern, comment: Self.ignoreComment)) == true
        else { return }
        StandardErrorLine.write(
            "woodcase: added \"\(Self.ignorePattern)\" to \(ignoreFile.url.path) — "
                + "the activity log is local state, not history."
        )
    }

    /// Creates the log file if it is not there yet, never truncating an existing one.
    private func createFileIfNeeded() throws {
        let descriptor = open(fileURL.path, O_WRONLY | O_CREAT, mode_t(0o644))
        guard descriptor >= 0 else {
            throw PenFileError.cannotOpen(url: fileURL, reason: FileLock.systemMessage(errno))
        }
        close(descriptor)
    }

    /// Moves the log aside and puts an empty file in its place.
    ///
    /// Only ever called while this process holds the log's exclusive lock, so no other
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
        let stem = base.deletingPathExtension().lastPathComponent
        for suffix in 1 ... 999 {
            let candidate = home.appendingPathComponent("\(stem)-\(suffix).jsonl", isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return home.appendingPathComponent("\(stem)-\(UUID().uuidString).jsonl", isDirectory: false)
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
