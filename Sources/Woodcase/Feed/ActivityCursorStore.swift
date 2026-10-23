//
//  ActivityCursorStore.swift
//  Woodcase
//

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Where each identity's last look at each file is kept: one small JSON file per
/// identity, `cursors/<identity>.json`, in the log's ``ActivityLog/stateDirectory``:
/// beside a bare file's log, and in a bundle's local `.woodcase/` — never in its shared
/// `history/`, since a cursor is one machine's place in it.
///
/// ```json
/// {"/Users/ben/Designs/home.pen":"1a2b3c-40960"}
/// ```
///
/// The store is what lets `woodcase changes` answer "since my last look" with no
/// argument: a turn-based agent runs it, reads what others did, and the next run starts
/// where this one ended. Keys are ``ActivityEvent/canonicalPath(for:)``, so two
/// spellings of one file share a cursor; values are ``ActivityCursor/token``s. An
/// identity is percent-encoded into the file name, so no name can reach outside the
/// directory.
///
/// A save is a read–modify–write under ``FileLock``, so two processes saving for the
/// same identity — one agent following two files — never drop each other's entry.
public struct ActivityCursorStore: Friendly {
    /// A store beside a log.
    ///
    /// - Parameter log: The activity log the cursors point into; the store lives in its
    ///   ``ActivityLog/stateDirectory``.
    public init(log: ActivityLog) {
        self.log = log
        directory = log.stateDirectory.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    /// The log the cursors point into.
    public let log: ActivityLog

    /// The directory the per-identity files live in.
    public let directory: URL

    /// The directory's name inside the log's home.
    public static let directoryName = "cursors"

    /// How long a save waits for another process's save to finish.
    public static let defaultTimeout: Duration = .seconds(5)

    /// The cursor an identity last saved for a file.
    ///
    /// - Parameters:
    ///   - identity: The `--as` name.
    ///   - file: The .pen file; any spelling of its path.
    /// - Returns: The cursor, or `nil` when the identity never saved one for the file.
    /// - Throws: ``PenFileError/unreadable(url:reason:)`` when the identity's file exists
    ///   but is not a cursor file.
    public func cursor(identity: String, file: URL) throws -> ActivityCursor? {
        let url = fileURL(for: identity)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try Self.decode(data, at: url)[ActivityEvent.canonicalPath(for: file)]
            .flatMap(ActivityCursor.init(token:))
    }

    /// Saves where an identity's look at a file ended.
    ///
    /// - Parameters:
    ///   - cursor: The cursor to resume from next time.
    ///   - identity: The `--as` name.
    ///   - file: The .pen file; any spelling of its path.
    ///   - timeout: How long to wait for a concurrent save.
    /// - Throws: ``PenFileError`` when the directory cannot be made, the lock is not
    ///   granted in time, or the file cannot be written.
    public func save(
        _ cursor: ActivityCursor, identity: String, file: URL, timeout: Duration = defaultTimeout
    ) async throws {
        let url = fileURL(for: identity)
        try prepare(url)
        let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: timeout)
        defer { lock.release() }

        var cursors = try Self.decode(lock.contents(), at: url)
        cursors[ActivityEvent.canonicalPath(for: file)] = cursor.token
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        do {
            // A rename, so a reader never sees half a file; a saver queued on the old
            // inode notices the replacement and retries (FileLock.acquire).
            try encoder.encode(cursors).write(to: url, options: .atomic)
        } catch {
            throw PenFileError.writeFailed(url: url, reason: PenFileError.oneLineReason(error))
        }
    }

    /// The file an identity's cursors live in.
    ///
    /// - Parameter identity: The `--as` name.
    /// - Returns: `cursors/<identity>.json`, the name percent-encoded.
    public func fileURL(for identity: String) -> URL {
        let encoded = identity.addingPercentEncoding(withAllowedCharacters: Self.nameCharacters) ?? identity
        return directory.appendingPathComponent((encoded.isEmpty ? "%" : encoded) + ".json")
    }

    // MARK: - Private

    /// Letters, digits, `-` and `_`: everything else — a dot, a slash — is encoded.
    private static let nameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    /// Makes the directory, through the log's own preparation so local state is ignored
    /// exactly as it is on the first write (see ``ActivityLog/prepare(_:for:naming:)``), and the
    /// file, empty.
    private func prepare(_ url: URL) throws {
        try ActivityLog.prepare(log.stateDirectory, for: log.origin)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PenFileError.writeFailed(url: url, reason: PenFileError.oneLineReason(error))
        }
        // O_CREAT without O_TRUNC: creates the file to lock if it is missing, and leaves a
        // racing saver's contents alone if it is not.
        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw PenFileError.writeFailed(url: url, reason: FileLock.systemMessage(errno))
        }
        close(descriptor)
    }

    /// A cursor file's contents; an empty file is an empty map.
    private static func decode(_ data: Data, at url: URL) throws -> [String: String] {
        guard !data.isEmpty else { return [:] }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw PenFileError.unreadable(url: url, reason: "not a cursor file: \(PenFileError.oneLineReason(error))")
        }
    }
}
