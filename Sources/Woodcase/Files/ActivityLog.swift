//
//  ActivityLog.swift
//  Woodcase
//

import Foundation

/// The append-only JSONL history every committed edit is written to.
///
/// One ``ActivityEvent`` per line, in the order the operations were applied. The log is
/// the history, the feed the viewer tails, and the source `woodcase undo` replays.
/// Nothing reads it to reconstruct a document — the .pen file is the truth — so a lost
/// log costs history, not data.
///
/// ## Where it lives, and its two layouts
///
/// ``ActivityLogLocation`` decides, and is the only place that does; this type is handed
/// the answer.
///
/// - **A bare .pen file** (``Layout/single``) writes `.woodcase/activity.jsonl` at the
///   repository root above it, or beside the file when there is no repository, or
///   wherever `$WOODCASE_HOME` says. It is local, derived state: the first append in a
///   repository adds `.woodcase/` to that repository's `.gitignore`.
/// - **A `.umbra` bundle** (``Layout/perWriter``) keeps a **shared** history in
///   `<bundle>/history/`: one file per ``HistoryWriter`` — `ben@grace.jsonl`,
///   `claude@grace.jsonl` — each appended only by its writer, so Git and file-sync
///   services never merge two writers' lines in one file. It is meant to be committed
///   and synced with the document, so it never touches the repository's `.gitignore`,
///   and its rows carry no absolute `file` path. ``ActivityReader`` merges the writers'
///   files by time. The bundle's local state — views, cursors, temporary files — stays
///   in its `.woodcase/` (``stateDirectory``), which the bundle's own `.gitignore`
///   ignores.
///
/// ```swift
/// let log = ActivityLogLocation.log(for: url)
/// try await log.append(recorder.events, as: "ben")
/// ```
///
/// Tests inject a directory with ``init(home:origin:device:)`` rather than mutating the
/// process environment.
///
/// ## Two processes, no torn lines
///
/// An append takes an exclusive `flock(2)` on the file it writes — the same lock a
/// ``PenFileTransaction`` takes on a .pen file — and writes every line of the batch in
/// one pass at the end of the file. Two `woodcase` processes appending at the same
/// instant therefore produce whole, separate lines rather than one interleaved mess.
/// Readers do not take the lock: ``ActivityReader`` never consumes a line that has no
/// newline yet, which is the same guarantee at a fraction of the cost.
///
/// ## Rotation
///
/// Before appending, a file already at or past ``rotationThreshold`` is renamed to
/// `<name>.<timestamp>.jsonl` beside itself and a fresh empty file takes its place, so
/// a live file never grows without bound. In a bundle each writer's file rotates on its
/// own. The rename happens under the lock, so only one process rotates a given file. A
/// follower notices because the file it resumes into is shorter than its offset — see
/// ``ActivityReader/Page/restarted``.
public struct ActivityLog: Friendly {
    /// Uses an explicit directory, whatever the environment says.
    ///
    /// - Parameters:
    ///   - home: The directory the log lives in — for a bundle, its `history/`. Created
    ///     on first append.
    ///   - origin: Why it is that directory. The default, ``Origin/directory``, is the
    ///     answer for a caller that chose the path itself — a test, an editor — and
    ///     leaves no `.gitignore` line behind. ``Origin/bundle(root:)`` makes it a
    ///     bundle's shared history, one file per writer.
    ///   - device: This device's name in a bundle's writer files; `nil` resolves
    ///     ``HistoryWriter/currentDevice(environment:)`` when appending.
    public init(home: URL, origin: Origin = .directory, device: String? = nil) {
        self.home = home
        self.origin = origin
        self.device = device
    }

    /// The environment variable that moves a bare file's log directory.
    ///
    /// One name, defined by ``WoodcaseHome/environmentVariable``: it moves the caches too.
    public static let homeEnvironmentVariable = WoodcaseHome.environmentVariable

    /// The directory, at a repository root, beside a .pen file or inside a bundle, that
    /// holds local state: a bare file's log, and every log's views and cursors.
    ///
    /// The same name ``WoodcaseHome`` uses in a user's home directory.
    public static let directoryName = WoodcaseHome.directoryName

    /// The directory inside a bundle that holds its shared history.
    ///
    /// Visible, unlike ``directoryName``: it is the document's own history, meant to be
    /// committed and synced, and a person should see it — and its size — in the bundle.
    public static let historyDirectoryName = "history"

    /// The `.gitignore` line that keeps local state out of a repository's history.
    public static let ignorePattern = "\(directoryName)/"

    /// The comment written above ``ignorePattern`` when it is added to a repository's
    /// `.gitignore`.
    public static let ignoreComment =
        "Woodcase activity log (local history of .pen edits; the .pen files are the truth)"

    /// The comment written above ``ignorePattern`` in a bundle's own `.gitignore`.
    public static let bundleIgnoreComment =
        "Woodcase local state (views, cursors, temporary files); history/ is shared and committed"

    /// A bare file's log's name inside ``home``.
    public static let fileName = "activity.jsonl"

    /// The size at which a live file is moved aside before the next append.
    public static let rotationThreshold: UInt64 = 8 * 1024 * 1024

    /// How long an append waits for another process to release the log's lock.
    public static let defaultTimeout: Duration = .seconds(5)

    /// The directory the log lives in: a bare file's `.woodcase`, or a bundle's `history`.
    public let home: URL

    /// Why the log is in ``home`` — what ``ActivityLogLocation`` decided.
    public let origin: Origin

    /// This device's name in a bundle's writer files — `grace` in `ben@grace.jsonl`;
    /// `nil` resolves ``HistoryWriter/currentDevice(environment:)`` when appending.
    /// Ignored by a bare file's log.
    public var device: String?

    /// How the log is laid out on disk, which follows from its ``origin``.
    public var layout: Layout {
        origin.holdsOneDocument ? .perWriter : .single
    }

    /// Where local state beside this log goes — the ``ViewLog`` and the
    /// ``ActivityCursorStore``: ``home`` for a bare file's log, the bundle's `.woodcase`
    /// for a bundle's history, which is shared and must not hold either.
    public var stateDirectory: URL {
        guard case let .bundle(root) = origin else { return home }
        return root.appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    /// The live log file for a bare file's log; for a bundle's history, which is one file
    /// per writer, the history directory itself.
    public var fileURL: URL {
        switch layout {
        case .single: home.appendingPathComponent(Self.fileName, isDirectory: false)
        case .perWriter: home
        }
    }

    /// The writer a bundle's append goes to for an identity on this log's ``device``.
    ///
    /// - Parameter identity: The writer's `--as` name.
    /// - Returns: The writer.
    public func writer(for identity: String) -> HistoryWriter {
        HistoryWriter(identity: identity, device: device ?? HistoryWriter.currentDevice())
    }

    /// Appends events to the log, creating the directory and file if needed.
    ///
    /// Every line is written in one pass under an exclusive lock, so a batch is never
    /// split by another writer. An empty batch does nothing at all — it does not even
    /// create the file.
    ///
    /// In a bundle's history the batch goes to the writer's own file, `identity@device`
    /// (``writer(for:)``), and each row is written without its ``ActivityEvent/file``.
    ///
    /// - Parameters:
    ///   - events: The events to append, in the order they were applied.
    ///   - identity: Who is appending: in a bundle, whose file the rows go to. `nil`
    ///     takes the first row's identity that is not ``ActivityEvent/unattributed`` —
    ///     an ``ActivityEvent/Kind/external`` row names nobody, but the writer who noticed
    ///     it appends it — or the unattributed writer when every row is. Ignored by a
    ///     bare file's log, which is one file.
    ///   - timeout: How long to wait for another process to release the file's lock.
    /// - Throws: ``PenFileError/writeFailed(url:reason:)`` if the directory or the line
    ///   cannot be written, ``PenFileError/cannotOpen(url:reason:)`` if the file cannot be
    ///   opened, or ``PenFileError/lockTimeout(url:timeout:)`` if another process holds
    ///   the lock past `timeout`. Every case names the log file, not the .pen file.
    public func append(
        _ events: [ActivityEvent],
        as identity: String? = nil,
        timeout: Duration = defaultTimeout
    ) async throws {
        guard !events.isEmpty else { return }

        let target: JSONLinesFile
        var rows = events
        switch layout {
        case .single:
            target = lines
        case .perWriter:
            let name = identity
                ?? events.first { $0.identity != ActivityEvent.unattributed }?.identity
                ?? ActivityEvent.unattributed
            target = history.file(for: writer(for: name))
            for index in rows.indices {
                rows[index].file = ""
            }
        }

        let encoder = ActivityEvent.makeEncoder()
        var payload = Data()
        for row in rows {
            try payload.append(row.jsonLine(using: encoder))
            payload.append(JSONLinesFile.newline)
        }

        try prepareDirectory()
        try await target.append(payload, timeout: timeout)
    }

    /// The name a bare file's log rotated at `date` is moved to:
    /// `activity.20260829T163104Z.jsonl`.
    ///
    /// The timestamp is ISO-8601 basic format in UTC — no separators, because a `:` in a
    /// file name is awkward on every platform that has ever had a Finder.
    ///
    /// - Parameter date: When the rotation happened.
    /// - Returns: The archive's URL, beside the live log.
    public func archiveURL(rotatedAt date: Date) -> URL {
        lines.archiveURL(rotatedAt: date)
    }

    /// A bare file's log underneath: locking, appending and rotation.
    var lines: JSONLinesFile {
        JSONLinesFile(home: home, stem: Self.fileStem, rotationThreshold: Self.rotationThreshold)
    }

    /// A bundle's history underneath: one ``JSONLinesFile`` per writer.
    var history: HistoryFiles {
        HistoryFiles(directory: home, rotationThreshold: Self.rotationThreshold)
    }

    /// Creates ``home`` if it is not there yet, and keeps local state out of Git: see
    /// ``prepare(_:for:naming:)``.
    func prepareDirectory() throws {
        try Self.prepare(home, for: origin, naming: fileURL)
    }

    /// Creates a directory a log or its local state lives in, the first time, and keeps
    /// local state out of Git.
    ///
    /// For a repository's log that is the `.woodcase/` line in the repository's
    /// `.gitignore`. For a bundle it is the same line in the bundle's own `.gitignore`,
    /// written inside the bundle — the shared `history/` is committed, and the
    /// repository's file is never touched. Elsewhere nothing is written.
    ///
    /// - Parameters:
    ///   - directory: The directory: ``home``, ``stateDirectory`` or one inside it.
    ///   - origin: The log's origin.
    ///   - url: The file a failure names — the log the caller was about to write;
    ///     `directory` itself when `nil`.
    /// - Throws: ``PenFileError/writeFailed(url:reason:)`` when the directory cannot be
    ///   created.
    static func prepare(_ directory: URL, for origin: Origin, naming url: URL? = nil) throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PenFileError.writeFailed(url: url ?? directory, reason: PenFileError.oneLineReason(error))
        }
        switch origin {
        case let .repository(root):
            ignoreInRepository(root)
        case let .bundle(root):
            _ = try? RepositoryIgnoreFile(root: root).addIfMissing(ignorePattern, comment: bundleIgnoreComment)
        case .environmentOverride, .directory:
            break
        }
    }

    // MARK: - Private

    /// The name of a bare file's live log without `.jsonl`; archives are
    /// `activity.<stamp>.jsonl`.
    private static let fileStem = "activity"

    /// Adds `.woodcase/` to a repository's `.gitignore`, once.
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
    ///
    /// - Parameter root: The repository root.
    private static func ignoreInRepository(_ root: URL) {
        let ignoreFile = RepositoryIgnoreFile(root: root)
        guard (try? ignoreFile.addIfMissing(ignorePattern, comment: ignoreComment)) == true
        else { return }
        StandardErrorLine.write(
            "woodcase: added \"\(ignorePattern)\" to \(ignoreFile.url.path) — "
                + "the activity log is local state, not history."
        )
    }
}
