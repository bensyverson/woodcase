//
//  PenFileTransaction+Save.swift
//  Woodcase
//

import Foundation

public extension PenFileTransaction {
    /// How an app's save of its session ended.
    enum SaveOutcome: Friendly {
        /// The file now holds the snapshot, and the rows of the changes it includes are
        /// in the log.
        case wrote

        /// The file already held the snapshot's document byte for byte; nothing was
        /// written or logged.
        case unchanged

        /// The file no longer holds what the session last synced — someone wrote it
        /// since. Nothing was written or logged. Submit `found` to the session as
        /// ``SessionOrigin/file(_:author:)``, then save again.
        ///
        /// - Parameters:
        ///   - found: The document the file holds now.
        ///   - lineage: What the activity log says about it: ``LogLineage/current(_:)``
        ///     names the row — and so the writer — that explains it.
        case fileChanged(found: PenDocument, lineage: LogLineage)

        /// Whether the file now holds the snapshot, so the session can be told with
        /// ``DocumentSession/noteSynced(_:)``.
        public var isSynced: Bool {
            switch self {
            case .wrote, .unchanged: true
            case .fileChanged: false
            }
        }
    }

    /// Saves a long-lived session's document to its file, under the lock, and logs the
    /// changes that produced it — an app's save path.
    ///
    /// The same contract as a CLI verb's write, from a process that keeps its document
    /// open: the file is locked exclusively, the document is written in the CLI's pretty,
    /// canonical bytes (``PenParser/encodeForFile(_:)``) by a temporary file and a
    /// rename, and the ``CommittedChange/activity`` rows of `changes` are appended under
    /// the session's author — so an agent reading the log sees `ben`, not an
    /// ``ActivityEvent/Kind/external`` row, and `woodcase undo` can step through the
    /// app's edits.
    ///
    /// Before writing, under the lock, the save checks that the file still holds what
    /// the session last synced (``DocumentSnapshot/syncedRevision``). If another writer
    /// got there first, nothing is written and the outcome is
    /// ``SaveOutcome/fileChanged(found:lineage:)``: merge `found` and save again, so an
    /// agent's write is never overwritten. If the file holds that revision but the log
    /// does not explain it — an outside writer from before the session opened — an
    /// ``ActivityEvent/Kind/external`` row goes first, as a CLI transaction would record.
    /// And if the session folded in work that wrote no rows of its own after its last
    /// logged change — a file merge that kept local work, a collaborator's operations —
    /// a ``ActivityEvent/Kind/merge`` row goes last, so the log still explains the
    /// saved file.
    ///
    /// Nothing here touches the session, so the save takes only Sendable values and runs
    /// off the caller's actor: snapshot on the main actor, save in a task, then report
    /// a ``SaveOutcome/isSynced`` outcome back with ``DocumentSession/noteSynced(_:)``.
    ///
    /// ```swift
    /// let snapshot = session.snapshot()
    /// let outcome = try await PenFileTransaction.save(snapshot, changes: unsaved, to: url)
    /// switch outcome {
    /// case .wrote, .unchanged:
    ///     session.noteSynced(snapshot)
    ///     unsaved.removeAll { $0.sequence <= snapshot.sequence }
    /// case let .fileChanged(found, lineage):
    ///     unsaved.append(try session.submit(.file(found, author: lineage.writer)))
    ///     // and save again
    /// }
    /// ```
    ///
    /// See <doc:Session> under "Saving from an app" for what the app must do around it.
    ///
    /// - Parameters:
    ///   - snapshot: The session's document, from ``DocumentSession/snapshot()``.
    ///   - changes: The committed changes the file does not hold yet. Only those the
    ///     snapshot includes — ``CommittedChange/sequence`` at most the snapshot's — are
    ///     logged; pass later ones again with the next save.
    ///   - url: The .pen file.
    ///   - log: Where rows go; `nil` resolves the file's own log through
    ///     ``ActivityLogLocation``.
    ///   - timeout: How long to wait for another holder of the file's lock.
    /// - Returns: How the save ended.
    /// - Throws: ``SessionError/fileStateUnknown`` for a snapshot of a session that never
    ///   knew its file's contents; ``PenFileError`` if the file cannot be opened, locked
    ///   or written, or the log appended to; ``PenParserError`` if the file is not a
    ///   readable .pen document; ``PenFormatWriteRefusal`` if it declares another major
    ///   version.
    @discardableResult
    @concurrent
    static func save(
        _ snapshot: DocumentSnapshot,
        changes: [CommittedChange],
        to url: URL,
        log: ActivityLog? = nil,
        timeout: Duration = defaultTimeout
    ) async throws -> SaveOutcome {
        guard let expected = snapshot.syncedRevision else { throw SessionError.fileStateUnknown }
        let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: timeout)
        defer { lock.release() }

        let parsed = try parse(lock)
        try parsed.requireWritableFormat(at: url)
        // The revision is a content hash of the document alone, so a plain flattening
        // answers it; the read context a CLI transaction attaches does not change it.
        let found = EditableDocument(from: parsed).documentRevision
        let activity = log ?? ActivityLogLocation.log(for: url)
        let lineage = try LogLineage.read(url, at: found, from: activity)
        guard found == expected else {
            return .fileChanged(found: parsed, lineage: lineage)
        }

        let updated = try encode(snapshot.document, for: url)
        guard try updated != encode(parsed, for: url) else { return .unchanged }
        try write(updated, replacing: lock)

        try await activity.append(saveRows(for: snapshot, changes: changes, lineage: lineage, at: url))
        return .wrote
    }
}
