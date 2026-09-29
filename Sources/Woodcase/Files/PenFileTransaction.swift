//
//  PenFileTransaction.swift
//  Woodcase
//

import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// Runs one stateless edit against one stateful .pen file.
///
/// A transaction is the whole of a command's contact with the file: it locks the
/// file, parses it, hands the caller an ``EditableDocument``, and — only if the
/// document actually changed — writes the result back atomically before releasing
/// the lock. Nothing is retained between calls, so every CLI verb, every viewer
/// refresh and every editor save is the same shape:
///
/// ```swift
/// let outcome = try await PenFileTransaction.run(at: url) { document in
///     try document.apply(.updateCommon(
///         EditOperation.UpdateCommon(nodeID: "jSUCH", common: renamed)
///     ))
///     return document.nodes.count
/// }
/// print(outcome.didWrite)   // true — the rename changed the document
/// ```
///
/// ## The lock
///
/// The lock is a `flock(2)` advisory lock on the .pen file itself, not a sidecar:
/// another tool opening the same path shares it. Being advisory, it stops only
/// participants — an editor writing the file without asking for the lock is not
/// blocked. Waiting is bounded: a lock still held after `timeout` fails with
/// ``PenFileError/lockTimeout(url:timeout:)`` rather than hanging.
///
/// ## Not writing
///
/// After the body returns, the materialized document is encoded with
/// ``PenParser/encodeForFile(_:)`` and compared against the same encoding of what
/// was parsed. Equal bytes mean no write at all: the file's contents *and* its
/// modification date are left exactly as they were, so a read-shaped command that
/// happens to go through ``run(at:timeout:effect:fonts:isolation:_:)`` never looks like an edit to a file
/// watcher. A body that throws also writes nothing.
///
/// ## Writing
///
/// The new contents go to a uniquely named temporary file in the same directory,
/// are given the original's permissions, and are then `rename(2)`d over it. A
/// reader either sees the whole old file or the whole new one, and a failure part
/// way through leaves the original intact and no temporary file behind.
///
/// ## Isolation
///
/// The body runs **where its caller runs**. Every entry point takes
/// `isolation: isolated (any Actor)? = #isolation`, so the actor is filled in at the
/// call site and no caller annotates anything: a CLI verb's body lands on the main
/// actor because the CLI's entry point is isolated to it, a SwiftUI editor's body lands
/// there for the same reason, and a script host or a test calling from its own actor
/// gets that actor. There is no hop to the main actor anywhere in here, and
/// no `@Sendable` on the body — it may capture and mutate whatever its caller owns.
///
/// The ``EditableDocument`` handed to the body is created and destroyed inside the
/// call and is not `Sendable`, so it cannot escape into another isolation domain; a
/// body that wants to keep something takes a value out through ``Outcome/value``.
///
/// ## Rehearsing
///
/// ``WriteEffect/dryRun`` runs the whole of the above and stops one step short: the
/// lock, the parse, the body, the guards, the settling and the encode all happen, and
/// then neither the rename nor the log append does. The outcome says ``Outcome/commit``
/// is ``Commit/previewed``, and the file, its revisions and the log are byte for byte
/// what they were. ``LintPreview`` is the companion that makes it worth doing.
///
/// ## The activity log
///
/// ``run(at:identity:log:timeout:effect:fonts:isolation:_:)`` hands the body an ``ActivityRecorder`` as well as
/// the document. Operations applied through the recorder become one ``ActivityEvent``
/// each — with their inverse and the revision they produced — appended to the
/// ``ActivityLog`` once the file is committed. A transaction that does not write appends
/// nothing; one opened *without* an identity still appends, under
/// ``ActivityEvent/unattributed``, because a write nobody can see is worse than a write
/// nobody claimed. See <doc:WoodcaseActivityLog>.
///
/// ## Writes from outside
///
/// A logged transaction asks the log, as it opens the file, whether the log explains
/// the bytes it just parsed — ``LogLineage``. It usually does; when it does not,
/// somebody rewrote the file without asking for the lock (another editor saving, a script with
/// a JSON parser), and the transaction records that fact as an
/// ``ActivityEvent/Kind/external`` row ahead of its own events and reports it in
/// ``Outcome/lineage`` for the caller to print. It is a note and never a refusal: the
/// outside edit may be perfectly legitimate, and refusing would strand the document.
///
/// The row is what makes it fire once. After it, the newest event's revision is the
/// file's revision again, so the next write is quiet — and `undo`, which cannot reverse
/// what woodcase did not do, has a boundary to stop at instead of a mismatch to guess
/// about.
///
/// ## Read context
///
/// The document handed to the body carries a ``PenReadContext`` the file itself does
/// not hold. The libraries its `imports` name are read once, here, relative to the file
/// — so `tree`, `lint`, `shot`, `render`, the viewer and a script all expand the same
/// imported instances, and a library that is missing is a ``PenImportProblem`` for
/// `lint` to report rather than a failed read. And the font resolver the caller passes
/// as `fonts:` is the one every settled read of the document registers fonts through:
/// the command line and the viewer name theirs, and the `nil` default measures in the
/// faces the process already has, so a test that forgets cannot reach the user's cache.
/// Nothing in the context is ever written back.
///
/// ## Legacy files
///
/// ``PenParser`` migrates an older 2.x document on the way in, so the body always
/// sees the current model. A transaction does *not* rewrite a legacy file just for
/// having read it — the comparison is model against model, and an unedited legacy
/// file compares equal. The first real edit writes the whole file in the current
/// format. Deliberate migration is `woodcase migrate`'s job, not a side effect of
/// reading — and it too runs under the lock, through
/// ``migrate(at:identity:log:timeout:effect:rewritingCurrent:diagnostics:)``, which
/// compares bytes rather than models and records a ``ActivityEvent/Kind/migrate`` row.
///
/// ## New files
///
/// ``create(at:document:identity:log:effect:)`` writes a file that does not exist yet,
/// under a lock taken before the file appears at its path, and records the file's
/// first event, ``ActivityEvent/Kind/new``. So every byte woodcase writes to a .pen
/// file — an edit, a migration, a creation — is in the log.
///
/// ## Newer and foreign versions
///
/// A file from a newer Pen of the same major is written back declaring its own version,
/// never the model's. A file of another major is read-only: ``read(at:timeout:diagnostics:fonts:isolation:_:)``
/// works, and every `run` throws ``PenFormatWriteRefusal`` before its body runs — a dry
/// run too, since the write it rehearses would be refused. See <doc:PenEngine>.
public enum PenFileTransaction {
    /// How a transaction ended: whether the file changed, and why not when it did not.
    ///
    /// Three answers rather than a bool, because "nothing was written" has two very
    /// different reasons and a caller branching on them needs to tell them apart: the
    /// edit was a no-op, or the edit was real and this was a rehearsal. Naming the fact
    /// keeps ``Outcome/didWrite`` and ``Outcome/wouldWrite`` honest at the same time.
    public enum Commit: String, Friendly, CaseIterable {
        /// The file was rewritten and the events appended.
        case wrote

        /// The document the body left behind encodes to the bytes it was given, so
        /// there was nothing to write — or the transaction was read-only.
        case unchanged

        /// The body's edit would have been written, and ``WriteEffect/dryRun`` threw it
        /// away. Nothing on disk moved.
        case previewed
    }

    /// What a transaction produced: the body's value, and how it ended.
    ///
    /// ``Commit/wrote`` is the seam the activity log hooks into — it marks the one point
    /// where a transaction commits, and so the one point where events are appended.
    public struct Outcome<Value: Sendable>: Sendable {
        /// Creates an outcome.
        ///
        /// - Parameters:
        ///   - value: The value the transaction's body returned.
        ///   - commit: How the transaction ended.
        ///   - url: The file the transaction ran against.
        ///   - lineage: What the activity log said about the file's bytes when the
        ///     transaction opened it. ``LogLineage/unlogged`` — the default — is what a
        ///     transaction that read no log answers.
        public init(value: Value, commit: Commit, url: URL, lineage: LogLineage = .unlogged) {
            self.value = value
            self.commit = commit
            self.url = url
            self.lineage = lineage
        }

        /// The value the transaction's body returned.
        public var value: Value

        /// How the transaction ended.
        public var commit: Commit

        /// The file the transaction ran against.
        public var url: URL

        /// What the activity log said about the file's bytes when the transaction
        /// opened it.
        ///
        /// ``LogLineage/diverged(since:found:)`` is the one a caller acts on: somebody
        /// rewrote the file behind the log's back, and ``LogLineage/note(naming:)`` is
        /// the sentence to print. A transaction that reads no log — ``read(at:timeout:diagnostics:fonts:isolation:_:)``
        /// and the unlogged ``run(at:timeout:effect:fonts:isolation:_:)`` — always answers
        /// ``LogLineage/unlogged``, because it asked nobody.
        public var lineage: LogLineage

        /// Whether the transaction wrote the file.
        ///
        /// `false` for a no-op body, for a read, and for a dry run — a dry run writes
        /// nothing by definition. Ask ``wouldWrite`` what the edit itself amounted to.
        public var didWrite: Bool {
            commit == .wrote
        }

        /// Whether the body's edit changed the document at all.
        ///
        /// `true` for a write that landed and for a dry run that would have landed;
        /// `false` only when the body left the document encoding to the bytes it was
        /// handed.
        public var wouldWrite: Bool {
            commit != .unchanged
        }
    }

    /// The default time a transaction waits for a competing lock holder.
    public static let defaultTimeout: Duration = .seconds(5)

    /// Opens a .pen file for editing, runs `body` against it, and writes back any change.
    ///
    /// Nothing is logged, because the body is handed no ``ActivityRecorder`` to log
    /// through — not because the edit is unattributed. This is the shape for a body that
    /// mutates a scratch copy, or one whose changes are not history. Use
    /// ``run(at:identity:log:timeout:effect:fonts:isolation:_:)`` for an edit that belongs in the log, with or
    /// without a writer's name.
    ///
    /// - Parameters:
    ///   - url: The .pen file to edit.
    ///   - timeout: How long to wait for another holder to release the file's lock.
    ///   - effect: Whether to keep the result. ``WriteEffect/dryRun`` runs everything and
    ///     writes nothing.
    ///   - fonts: The font resolver the document settles through — see *Read context*.
    ///     `nil` measures in the faces the process already has.
    ///   - isolation: The actor the caller runs on, filled in by `#isolation`. The body
    ///     runs there; see *Isolation* above.
    ///   - body: The edit. It runs on the caller's isolation with a freshly parsed
    ///     ``EditableDocument``; whatever it returns becomes ``Outcome/value``.
    ///     If it throws, the file is left untouched and the error propagates.
    /// - Returns: The body's value and how the transaction ended.
    /// - Throws: ``PenFileError`` if the file cannot be opened, locked or written,
    ///   ``PenParserError`` if its contents are not a readable .pen document,
    ///   ``PenFormatWriteRefusal`` if they declare another major version;
    ///   anything the body throws, unchanged.
    @discardableResult
    public static func run<Value: Sendable>(
        at url: URL,
        timeout: Duration = defaultTimeout,
        effect: WriteEffect = .commit,
        fonts: GoogleFontResolver? = nil,
        isolation _: isolated (any Actor)? = #isolation,
        _ body: (EditableDocument) throws -> Value
    ) async throws -> Outcome<Value> {
        try await run(at: url, identity: nil, timeout: timeout, effect: effect, fonts: fonts) { document, _ in
            try body(document)
        }
    }

    /// Opens a .pen file for editing, runs `body` against it, and — if it wrote —
    /// appends what the body did to the activity log.
    ///
    /// The body is handed an ``ActivityRecorder`` beside the document. Operations
    /// applied through the recorder are logged; operations applied straight to the
    /// document are not, which is the one way to make an edit this transaction cannot
    /// account for. There is no reason to want that.
    ///
    /// ```swift
    /// try await PenFileTransaction.run(at: url, identity: "ana") { document, recorder in
    ///     try recorder.apply(.updateCommon(rename))
    /// }
    /// ```
    ///
    /// Events are appended **after** the file is committed, so a transaction that throws
    /// or that changes nothing logs nothing. Each event carries the document's revision
    /// as of its own operation, and every event of one transaction shares a batch id.
    ///
    /// - Parameters:
    ///   - url: The .pen file to edit.
    ///   - identity: The writer's name — the CLI's `--as`. `nil` is the unattributed
    ///     writer: the events are recorded exactly as they would be for a named one, and
    ///     carry ``ActivityEvent/unattributed`` as their identity.
    ///   - log: Where events go. `nil` — the default — resolves the .pen file's own log
    ///     through ``ActivityLogLocation``, which is what every verb wants.
    ///   - timeout: How long to wait for another holder to release the file's lock.
    ///   - effect: Whether to keep the result. ``WriteEffect/dryRun`` takes the same
    ///     exclusive lock, runs the same body and settles the same document, then skips
    ///     both the write and the log append — so the file's bytes, its revisions, the
    ///     log and the `.gitignore` line the log would have added are untouched.
    ///   - fonts: The font resolver the document settles through — see *Read context*.
    ///     `nil` measures in the faces the process already has.
    ///   - isolation: The actor the caller runs on, filled in by `#isolation`. The body
    ///     runs there; see *Isolation* above.
    ///   - body: The edit. It runs on the caller's isolation with a freshly parsed
    ///     ``EditableDocument`` and a recorder for it.
    /// - Returns: The body's value and how the transaction ended.
    /// - Throws: ``PenFileError`` if the file cannot be opened, locked or written,
    ///   ``PenParserError`` if its contents are not a readable .pen document,
    ///   ``PenFormatWriteRefusal`` if they declare another major version;
    ///   anything the body throws, unchanged. A failure to append to the log is
    ///   also a ``PenFileError``, naming the *log* file — the edit itself is on disk by
    ///   then, and the error says which file could not be written.
    @discardableResult
    public static func run<Value: Sendable>(
        at url: URL,
        identity: String?,
        log: ActivityLog? = nil,
        timeout: Duration = defaultTimeout,
        effect: WriteEffect = .commit,
        fonts: GoogleFontResolver? = nil,
        isolation _: isolated (any Actor)? = #isolation,
        _ body: (EditableDocument, ActivityRecorder) throws -> Value
    ) async throws -> Outcome<Value> {
        let lock = try await FileLock.acquire(url, mode: .exclusive, timeout: timeout)
        defer { lock.release() }

        let parsed = try parse(lock)
        // Before the body, not before the write: a verb refused here has done nothing,
        // and a dry run is refused too, because the write it rehearses would be.
        try parsed.requireWritableFormat(at: url)
        let batch = UUID().uuidString
        let editable = editableDocument(from: parsed, at: url, fonts: fonts)
        let activity = log ?? ActivityLogLocation.log(for: url)
        let lineage = try LogLineage.read(url, at: editable.documentRevision, from: activity)
        let recorder = ActivityRecorder(
            document: editable, file: url, identity: identity, batch: batch
        )
        // First, so that the history reads in order: whatever this transaction goes on
        // to write happened *after* the outside edit, and the row says where the log's
        // account of the file resumes.
        if let external = lineage.external(naming: url) {
            recorder.record(external)
        }
        let value = try body(editable, recorder)
        let materialized = editable.materialize()
        let events = recorder.events

        let updated = try encode(materialized, for: url)
        guard try updated != encode(parsed, for: url) else {
            return Outcome(value: value, commit: .unchanged, url: url, lineage: lineage)
        }
        // The rehearsal ends here, with the bytes it would have written in hand and
        // nowhere to put them. Skipping the append is what also spares the log's
        // directory and its `.gitignore` line.
        guard effect == .commit else {
            return Outcome(value: value, commit: .previewed, url: url, lineage: lineage)
        }
        try write(updated, replacing: lock)
        try await activity.append(events)
        return Outcome(value: value, commit: .wrote, url: url, lineage: lineage)
    }

    /// Opens a .pen file for reading and runs `body` against it, never writing.
    ///
    /// The lock taken is shared, so any number of reads proceed together; a read
    /// still waits for a writer, and gives up the same way ``run(at:timeout:effect:fonts:isolation:_:)`` does.
    /// The body gets a real ``EditableDocument`` and may edit it freely — the edits
    /// are simply discarded, which is what makes this safe to use for derived
    /// views that need to mutate a scratch copy.
    ///
    /// - Parameters:
    ///   - url: The .pen file to read.
    ///   - timeout: How long to wait for a writer to release the file's lock.
    ///   - diagnostics: A collector for the warnings the parse itself produces — the
    ///     version gate's, and the legacy migrator's. Passing one is the only way to
    ///     see them, and it sees them *under the lock*, so they describe the same bytes
    ///     the body is handed. `nil` discards them.
    ///   - fonts: The font resolver the document settles through — see *Read context*.
    ///     `nil` measures in the faces the process already has.
    ///   - isolation: The actor the caller runs on, filled in by `#isolation`. The body
    ///     runs there; see *Isolation* above.
    ///   - body: The read. It runs on the caller's isolation; whatever it returns becomes
    ///     ``Outcome/value``.
    /// - Returns: The body's value, with ``Outcome/didWrite`` always `false`.
    /// - Throws: ``PenFileError`` if the file cannot be opened or locked,
    ///   ``PenParserError`` if its contents are not a readable .pen document;
    ///   anything the body throws, unchanged.
    @discardableResult
    public static func read<Value: Sendable>(
        at url: URL,
        timeout: Duration = defaultTimeout,
        diagnostics: PenDiagnosticCollector? = nil,
        fonts: GoogleFontResolver? = nil,
        isolation _: isolated (any Actor)? = #isolation,
        _ body: (EditableDocument) throws -> Value
    ) async throws -> Outcome<Value> {
        let lock = try await FileLock.acquire(url, mode: .shared, timeout: timeout)
        defer { lock.release() }

        let parsed = try parse(lock, diagnostics: diagnostics)
        let value = try body(editableDocument(from: parsed, at: url, fonts: fonts))
        return Outcome(value: value, commit: .unchanged, url: url)
    }

    // MARK: - Shared with the rewrite and create entry points

    /// Reads and parses the locked file.
    ///
    /// A ``PenParserError`` is let through as itself, naming the locked file: it is
    /// already the more specific error of the two, and re-wrapping it as a
    /// ``PenFileError`` would flatten the decoder's reason into a string and name the
    /// path twice. That is what makes a verb reading through a transaction print the
    /// same sentence as one calling ``PenParser/parse(contentsOf:diagnostics:)`` itself.
    ///
    /// - Parameters:
    ///   - lock: The held lock on the file to read.
    ///   - diagnostics: A collector for the parse's own warnings, or `nil`.
    /// - Returns: The parsed document.
    /// - Throws: ``PenParserError`` for anything the parser refuses, naming the file;
    ///   ``PenFileError/unreadable(url:reason:)`` for anything else raised on the way.
    static func parse(
        _ lock: FileLock,
        diagnostics: PenDiagnosticCollector? = nil
    ) throws -> PenDocument {
        let data = try lock.contents()
        do {
            return try PenParser.parse(data, from: lock.url, diagnostics: diagnostics)
        } catch let error as PenParserError {
            throw error
        } catch {
            throw PenFileError.unreadable(url: lock.url, reason: String(describing: error))
        }
    }

    /// Encodes a document in the canonical on-disk form.
    static func encode(_ document: PenDocument, for url: URL) throws -> Data {
        do {
            return try PenParser.encodeForFile(document)
        } catch {
            throw PenFileError.writeFailed(url: url, reason: String(describing: error))
        }
    }

    /// Writes `data` over the locked file: a temporary neighbour, then a rename.
    static func write(_ data: Data, replacing lock: FileLock) throws {
        let url = lock.url
        let temporary = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        do {
            try data.write(to: temporary)
        } catch {
            throw PenFileError.writeFailed(url: url, reason: String(describing: error))
        }

        if let permissions = lock.permissions {
            chmod(temporary.path, permissions)
        }

        guard rename(temporary.path, url.path) == 0 else {
            let failure = errno
            try? FileManager.default.removeItem(at: temporary)
            throw PenFileError.writeFailed(url: url, reason: FileLock.systemMessage(failure))
        }
    }
}

// `Outcome` is `Friendly` exactly as far as its payload allows: a transaction body
// may return anything `Sendable`, so the remaining conformances are conditional.

extension PenFileTransaction.Outcome: Equatable where Value: Equatable {}

extension PenFileTransaction.Outcome: Hashable where Value: Hashable {}

extension PenFileTransaction.Outcome: Codable where Value: Codable {}
