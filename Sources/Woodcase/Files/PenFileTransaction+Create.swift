//
//  PenFileTransaction+Create.swift
//  Woodcase
//

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public extension PenFileTransaction {
    /// Creates a .pen file holding `document`, and records it as the file's first event.
    ///
    /// This is `woodcase new`'s write. The file never exists unlocked or half written:
    /// the encoded document goes to a temporary neighbor, the lock is taken on that, and
    /// the neighbor is then hard-linked into place — `link(2)` refuses an existing path,
    /// so creating is atomic and never overwrites. A transaction that opens the new path
    /// a moment later waits on the same lock until the ``ActivityEvent/Kind/new`` event
    /// is appended, so the file's history starts with its creation.
    ///
    /// ```swift
    /// let outcome = try await PenFileTransaction.create(
    ///     at: url, document: PenDocument(children: []), identity: "ana"
    /// )
    /// print(outcome.value)   // the new file's document revision
    /// ```
    ///
    /// - Parameters:
    ///   - url: Where to create the file. Its directory must exist.
    ///   - document: What the file holds.
    ///   - identity: The writer's name — the CLI's `--as` — or `nil` for the
    ///     unattributed writer.
    ///   - log: Where the event goes. `nil` resolves the file's own log.
    ///   - effect: ``WriteEffect/dryRun`` checks and encodes, then creates nothing and
    ///     records nothing.
    /// - Returns: The new file's ``EditableDocument/documentRevision``, and how the
    ///   transaction ended.
    /// - Throws: ``PenFileError/cannotOpen(url:reason:)`` when something already exists
    ///   at `url`, ``PenFileError/writeFailed(url:reason:)`` when the file cannot be
    ///   written, and ``PenFormatWriteRefusal`` for a document of another major version.
    @discardableResult
    static func create(
        at url: URL,
        document: PenDocument,
        identity: String?,
        log: ActivityLog? = nil,
        effect: WriteEffect = .commit
    ) async throws -> Outcome<String> {
        try document.requireWritableFormat(at: url)
        let revision = EditableDocument(from: document).documentRevision
        let data = try encode(document, for: url)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw PenFileError.cannotOpen(url: url, reason: alreadyExists)
        }
        guard effect == .commit else {
            return Outcome(value: revision, commit: .previewed, url: url)
        }

        let temporary = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            throw PenFileError.writeFailed(url: url, reason: PenFileError.oneLineReason(error))
        }
        defer { unlink(temporary.path) }

        let lock = try await FileLock.acquire(temporary, mode: .exclusive, timeout: defaultTimeout)
        defer { lock.release() }
        guard link(temporary.path, url.path) == 0 else {
            let failure = errno
            throw failure == EEXIST
                ? PenFileError.cannotOpen(url: url, reason: alreadyExists)
                : PenFileError.writeFailed(url: url, reason: FileLock.systemMessage(failure))
        }

        let activity = log ?? ActivityLogLocation.log(for: url)
        try await activity.append([ActivityEvent(
            time: Date(), identity: identity ?? ActivityEvent.unattributed, file: url,
            op: .new, revision: revision, batch: UUID().uuidString
        )])
        return Outcome(value: revision, commit: .wrote, url: url)
    }

    /// Why a create was refused when its path was taken.
    private static let alreadyExists = "a file already exists there"
}
