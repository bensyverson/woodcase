//
//  PenFileTransaction+Migrate.swift
//  Woodcase
//

import Foundation

public extension PenFileTransaction {
    /// Rewrites a .pen file in the current format — or, for a file a newer Pen wrote, in
    /// its own — under the file's lock, and records the rewrite in the activity log.
    ///
    /// This is `woodcase migrate`'s write. It differs from ``run(at:identity:log:timeout:effect:isolation:_:)``
    /// in what it compares: a migration happens as a file is *read*, so the document an
    /// edit would compare is already migrated, and an unedited older file compares equal
    /// to itself. Here the comparison is bytes against bytes — the file as it is on disk
    /// against ``PenFileMigrator``'s canonical encoding of it.
    ///
    /// ```swift
    /// let outcome = try await PenFileTransaction.migrate(at: url, identity: "ana")
    /// print(outcome.value.writtenVersion, outcome.didWrite)   // "2.19" true
    /// ```
    ///
    /// A rewrite appends one ``ActivityEvent/Kind/migrate`` event. Its revision is the
    /// file's revision — which the rewrite does not change, because the parse already
    /// migrated the document — so the log keeps explaining the file, and `undo` passes
    /// over the row. When the log did not explain the file before the rewrite, the
    /// ``ActivityEvent/Kind/external`` row comes first, exactly as for an edit.
    ///
    /// - Parameters:
    ///   - url: The .pen file to rewrite.
    ///   - identity: The writer's name — the CLI's `--as` — or `nil` for the
    ///     unattributed writer.
    ///   - log: Where the event goes. `nil` resolves the file's own log.
    ///   - timeout: How long to wait for another holder to release the file's lock.
    ///   - effect: ``WriteEffect/dryRun`` does everything but the rename and the append.
    ///   - force: Whether to rewrite a file that already declares the model's version, or
    ///     a newer minor — `--force`. Without it such a file is left alone.
    ///   - diagnostics: A collector for what the parse and the migration report.
    /// - Returns: ``PenFileMigrator``'s outcome, and how the transaction ended:
    ///   ``Commit/unchanged`` when there was nothing to rewrite.
    /// - Throws: ``PenFileError`` if the file cannot be opened, locked or written,
    ///   ``PenParserError`` if it is not a readable .pen document, and
    ///   ``PenFormatWriteRefusal`` for another major version, which is never rewritten.
    @discardableResult
    static func migrate(
        at url: URL,
        identity: String?,
        log: ActivityLog? = nil,
        timeout: Duration = defaultTimeout,
        effect: WriteEffect = .commit,
        rewritingCurrent force: Bool = false,
        diagnostics: PenDiagnosticCollector? = nil
    ) async throws -> Outcome<PenFileMigrator.Outcome> {
        let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: timeout)
        defer { lock.release() }

        let original = try lock.contents()
        let migration = try PenFileMigrator.migrate(original, from: url, diagnostics: diagnostics)
        guard force || !migration.wasAlreadyCurrent, migration.data != original else {
            return Outcome(value: migration, commit: .unchanged, url: url)
        }

        let revision = try EditableDocument(from: PenParser.parse(migration.data, from: url)).documentRevision
        let activity = log ?? ActivityLogLocation.log(for: url)
        let lineage = try LogLineage.read(url, at: revision, from: activity)
        guard effect == .commit else {
            return Outcome(value: migration, commit: .previewed, url: url, lineage: lineage)
        }

        try write(migration.data, replacing: lock)
        let now = Date()
        let rewrite = ActivityEvent(
            time: now, identity: identity ?? ActivityEvent.unattributed, file: url,
            op: .migrate, revision: revision, batch: UUID().uuidString
        )
        try await activity.append([lineage.external(naming: url, at: now), rewrite].compactMap(\.self))
        return Outcome(value: migration, commit: .wrote, url: url, lineage: lineage)
    }
}
