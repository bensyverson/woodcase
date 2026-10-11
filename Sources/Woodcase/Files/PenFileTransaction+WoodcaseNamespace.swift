//
//  PenFileTransaction+WoodcaseNamespace.swift
//  Woodcase
//

import Foundation

public extension PenFileTransaction {
    /// Moves every old-style Woodcase metadata key in a .pen file under
    /// `metadata.woodcase`, as one logged, undoable edit.
    ///
    /// This is the second half of `woodcase migrate`. Unlike the format migration
    /// (``migrate(at:identity:log:timeout:effect:rewritingCurrent:diagnostics:)``), it
    /// changes the document — the keys move — so it is an ordinary edit through
    /// ``run(at:identity:log:timeout:effect:fonts:isolation:_:)``: its rows carry an
    /// inverse and `undo` reverses it. The edit is
    /// ``EditableDocument/oldStyleWoodcaseKeyMigration()``; a file with nothing to move
    /// is left untouched.
    ///
    /// ```swift
    /// let outcome = try await PenFileTransaction.moveOldStyleWoodcaseKeys(at: url, identity: "ana")
    /// print(outcome.value, outcome.didWrite)   // 3 true
    /// ```
    ///
    /// - Parameters:
    ///   - url: The .pen file.
    ///   - identity: The writer's name — the CLI's `--as` — or `nil` for the
    ///     unattributed writer.
    ///   - log: Where the events go. `nil` resolves the file's own log.
    ///   - timeout: How long to wait for another holder to release the file's lock.
    ///   - effect: ``WriteEffect/dryRun`` does everything but the write and the append.
    ///   - isolation: The actor the caller runs on, filled in by `#isolation`.
    /// - Returns: How many nodes' metadata moved, and how the transaction ended.
    /// - Throws: Whatever ``run(at:identity:log:timeout:effect:fonts:isolation:_:)`` throws.
    @discardableResult
    static func moveOldStyleWoodcaseKeys(
        at url: URL,
        identity: String?,
        log: ActivityLog? = nil,
        timeout: Duration = defaultTimeout,
        effect: WriteEffect = .commit,
        isolation _: isolated (any Actor)? = #isolation
    ) async throws -> Outcome<Int> {
        try await run(at: url, identity: identity, log: log, timeout: timeout, effect: effect) { document, recorder in
            let operations = document.oldStyleWoodcaseKeyMigration()
            if !operations.isEmpty {
                try recorder.apply(operations)
            }
            return operations.count
        }
    }
}
