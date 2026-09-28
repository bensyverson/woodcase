//
//  BatchApplier+Guards.swift
//  Woodcase
//

import Foundation

public extension BatchApplier {
    /// Checks every ``BatchGuard`` a transaction carries, before any of it has run.
    ///
    /// This is the entry gate. Call it once, as the first thing inside the transaction
    /// body — the moment the file lock is held and the document is parsed, and before a
    /// single edit is applied. Under the single-writer lock every foreign write strictly
    /// precedes that moment and every line of this transaction follows it, so a guard
    /// asks exactly *"has anyone else moved this since I read it?"* and a batch's own
    /// earlier lines can never trip a later line's guard.
    ///
    /// ```swift
    /// try await PenFileTransaction.run(at: url, identity: writer) { document, recorder in
    ///     try BatchApplier.checkGuards(operations, in: document, log: log, file: url)
    ///     return BatchApplier.apply(operations, to: document, recorder: recorder)
    /// }
    /// ```
    ///
    /// A failed guard throws, so the whole transaction is refused and nothing is
    /// written — guards are entry gates, not per-line statuses, and a batch whose line 30
    /// guarded a premise that moved must not apply lines 1 to 29 against it.
    /// ``apply(_:to:atomic:identity:recorder:)`` therefore does *not* check guards
    /// itself: it reports rather than throws, and a report is the wrong answer here.
    /// ``applyOne(_:to:recorder:)`` does check them, because a single verb's one line
    /// *is* the whole transaction.
    ///
    /// - Parameters:
    ///   - operations: The lines about to run. For a retry, pass only the lines that
    ///     will actually be re-run: a line that already applied moved its own subtree,
    ///     and re-asserting its premise would refuse the repair.
    ///   - document: The document as the transaction found it.
    ///   - log: The activity log, so a failure can name who wrote in between. `nil`
    ///     leaves the message without that clause rather than guessing.
    ///   - file: The .pen file being edited, which is what the log is filtered by.
    /// - Throws: ``BatchError/guardConflict(node:address:expected:actual:writer:)`` when a
    ///   pinned revision has moved, ``BatchError/guardNodeMissing(node:)`` when the pinned node
    ///   is not in the document, ``BatchError/guardOnTag(tag:)`` for a guard naming a
    ///   batch tag, and ``BatchError/guardWithoutTarget(verb:)`` for a bare guard on a
    ///   line that acts on no node.
    static func checkGuards(
        _ operations: [BatchOperation],
        in document: EditableDocument,
        log: ActivityLog? = nil,
        file: URL? = nil
    ) throws {
        for operation in operations {
            try checkGuards(
                operation.guards, pinning: operation.guardTarget, of: operation.verb.rawValue,
                in: document, log: log, file: file
            )
        }
    }

    /// Checks guards a *caller* carries rather than a line — `woodcase apply --guard`.
    ///
    /// `apply` acts on the whole file, so a bare pin on its command line pins the
    /// document; a `<node>=<rev>` pin names its own scope and is checked exactly as the
    /// same pin written on a line would be. Argv guards and line guards are asserted at
    /// the same door, in that order, so a batch is refused for whichever premise moved.
    ///
    /// - Parameters:
    ///   - guards: The pins the caller wrote.
    ///   - target: What a bare pin means for this caller — ``BatchOperation/GuardTarget/document``
    ///     for `apply`.
    ///   - verb: The verb's name, for the refusal a bare pin earns when there is nothing
    ///     for it to pin.
    ///   - document: The document as the transaction found it.
    ///   - log: The activity log, so a failure can name who wrote in between.
    ///   - file: The .pen file being edited, which is what that log is filtered by.
    /// - Throws: The same refusals ``checkGuards(_:in:log:file:)`` throws.
    static func checkGuards(
        _ guards: [BatchGuard],
        pinning target: BatchOperation.GuardTarget,
        of verb: String,
        in document: EditableDocument,
        log: ActivityLog? = nil,
        file: URL? = nil
    ) throws {
        for pin in guards {
            try check(pin, pinning: target, of: verb, in: document, log: log, file: file)
        }
    }

    // MARK: - One pin

    /// Checks one pin, resolving what it was read for.
    private static func check(
        _ pin: BatchGuard,
        pinning target: BatchOperation.GuardTarget,
        of verb: String,
        in document: EditableDocument,
        log: ActivityLog?,
        file: URL?
    ) throws {
        switch pin.scope {
        case .document:
            try checkDocument(pin, in: document, log: log, file: file)
        case let .node(address):
            try check(pin, at: address, in: document, log: log, file: file)
        case .target:
            switch target {
            case let .node(address):
                try check(pin, at: address, in: document, log: log, file: file)
            case .document:
                try checkDocument(pin, in: document, log: log, file: file)
            case .nothing:
                throw BatchError.guardWithoutTarget(verb: verb)
            }
        }
    }

    /// Checks a pin against one node's revision.
    private static func check(
        _ pin: BatchGuard,
        at address: NodeAddress,
        in document: EditableDocument,
        log: ActivityLog?,
        file: URL?
    ) throws {
        if let tag = address.tagName {
            throw BatchError.guardOnTag(tag: tag)
        }
        // An address that resolves to nothing is the world having moved — the node the
        // caller read is gone — which is the conflict a guard exists to report. Every
        // other resolution failure (an ambiguous path, above all) is a malformed
        // invocation, and the resolver's own message lists the candidates for it.
        let resolved: ResolvedNodeAddress
        do {
            resolved = try document.resolve(address)
        } catch let error as EditingError {
            guard case .addressNotFound = error else { throw error }
            throw BatchError.guardNodeMissing(node: address.description)
        }
        guard let actual = document.revision(of: resolved.targetID) else {
            throw BatchError.guardNodeMissing(node: address.description)
        }
        guard actual != pin.rev else { return }
        throw BatchError.guardConflict(
            node: BatchErrorMessage.name(resolved.targetID, in: document),
            address: address.description,
            expected: pin.rev,
            actual: actual,
            writer: writer(
                touching: document.revisionCoverage(of: resolved.targetID),
                log: log, file: file
            )
        )
    }

    /// Checks a pin against the whole document's revision.
    private static func checkDocument(
        _ pin: BatchGuard,
        in document: EditableDocument,
        log: ActivityLog?,
        file: URL?
    ) throws {
        let actual = document.documentRevision
        guard actual != pin.rev else { return }
        throw BatchError.guardConflict(
            node: "the document",
            address: nil,
            expected: pin.rev,
            actual: actual,
            writer: writer(touching: nil, log: log, file: file)
        )
    }

    // MARK: - Who moved it

    /// The identity that last wrote inside a pinned node's coverage, from the log.
    ///
    /// The log is the only record of *who*, and it is read only once a guard has already
    /// failed, so its cost never lands on a write that works. A `nil` answer means the
    /// log cannot say — it is missing, unreadable, or holds no event touching those
    /// nodes — and the message then simply omits the clause. An empty string is a real
    /// answer, ``ActivityEvent/unattributed``, and reads as "an unattributed write".
    ///
    /// - Parameters:
    ///   - coverage: The nodes whose content the pinned revision folds in, from
    ///     ``EditableDocument/revisionCoverage(of:)``; `nil` for a document-wide pin,
    ///     which any write at all can move.
    ///   - log: The log to read, or `nil` to skip the lookup.
    ///   - file: The .pen file whose events count.
    /// - Returns: The writer's `--as` name, or `nil` when the log cannot say.
    private static func writer(touching coverage: Set<String>?, log: ActivityLog?, file: URL?) -> String? {
        guard let log, let page = try? ActivityReader(log: log).read(file: file) else { return nil }
        guard let coverage else { return page.events.last?.identity }
        return page.events.last { !coverage.isDisjoint(with: $0.nodes) }?.identity
    }
}
