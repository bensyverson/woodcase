//
//  LogLineage.swift
//  Woodcase
//

import Foundation

/// Whether the activity log explains the bytes a .pen file holds right now.
///
/// One question, asked in two places. A ``PenFileTransaction`` asks it as it opens a
/// file, so a write can say out loud that somebody edited the document behind the
/// log's back; ``ActivityUndo`` asks it of each event it walks back through, because an
/// inverse is only exact while the file is still in the state that event produced.
/// Both go through this type, so there is one implementation of *does the log explain
/// this file*.
///
/// ## Why the comparison is proof, not a guess
///
/// An ``ActivityEvent/revision`` is the document's
/// ``EditableDocument/documentRevision`` *after* that operation, and a document
/// revision is a Merkle fold over the parsed model. So the newest event's revision
/// matching the parsed file's proves that woodcase wrote the file last and that nothing
/// has touched it since. A mismatch is the opposite proof: the bytes on disk are not
/// the bytes any recorded edit produced.
///
/// ```swift
/// let lineage = try LogLineage.read(url, at: document.documentRevision, from: log)
/// if let note = lineage.note(naming: url) {
///     print("note  \(note)")
/// }
/// ```
///
/// ## A file with no history is not a divergence
///
/// ``unlogged`` is a third answer on purpose. A file nobody has edited through woodcase
/// — a fresh checkout, a design exported from Pen — makes no claim either way, and
/// reporting it as an outside edit would cry wolf on the first write to every file.
public enum LogLineage: Friendly {
    /// Nothing is recorded for this file, so the log claims nothing about it.
    case unlogged

    /// The newest recorded event produced exactly the bytes the file now holds.
    case current(ActivityEvent)

    /// Something rewrote the file after the newest recorded event.
    ///
    /// - Parameters:
    ///   - since: The newest recorded event — the last state woodcase knows about.
    ///   - found: The revision the file was actually found at.
    case diverged(since: ActivityEvent, found: String)

    /// Judges a document revision against the newest event recorded for its file.
    ///
    /// - Parameters:
    ///   - documentRevision: The revision the file was parsed at.
    ///   - newest: The newest event recorded for that file, or `nil` if there is none.
    public init(documentRevision: String, newest: ActivityEvent?) {
        guard let newest else {
            self = .unlogged
            return
        }
        self = Self.explains(newest, at: documentRevision)
            ? .current(newest)
            : .diverged(since: newest, found: documentRevision)
    }

    /// Reads a log and judges a file against it.
    ///
    /// - Parameters:
    ///   - url: The .pen file in question.
    ///   - documentRevision: The revision it was parsed at.
    ///   - log: The log to read. Only its newest line for this file is decoded.
    /// - Returns: What the log says about those bytes.
    /// - Throws: Whatever ``ActivityReader/newest(file:)`` throws if the log exists but
    ///   cannot be read.
    public static func read(
        _ url: URL, at documentRevision: String, from log: ActivityLog
    ) throws -> LogLineage {
        try LogLineage(
            documentRevision: documentRevision,
            newest: ActivityReader(log: log).newest(file: url)
        )
    }

    /// Whether one event's revision is the file's, and so whether its inverse is exact.
    ///
    /// This is the whole of the comparison, in one place: ``ActivityUndo`` asks it of
    /// every candidate it walks back through, and ``init(documentRevision:newest:)``
    /// asks it of the newest event alone.
    ///
    /// - Parameters:
    ///   - event: The event to test.
    ///   - documentRevision: The revision the document is at right now.
    /// - Returns: `true` when the file holds precisely the state that event produced.
    public static func explains(_ event: ActivityEvent, at documentRevision: String) -> Bool {
        event.revision == documentRevision
    }

    /// The newest recorded event, or `nil` for a file with no history.
    public var newest: ActivityEvent? {
        switch self {
        case .unlogged: nil
        case let .current(event): event
        case let .diverged(since, _): since
        }
    }

    /// Whether something rewrote the file outside woodcase.
    public var isDiverged: Bool {
        if case .diverged = self { true } else { false }
    }

    /// The sentence a verb prints when it finds the file changed behind the log's back.
    ///
    /// It is a note and not a refusal because the edit may be perfectly legitimate —
    /// another editor saved, someone ran a script — and refusing would strand a real document.
    /// What the reader needs is to know that the history has a hole in it and where the
    /// hole starts.
    ///
    /// - Parameter url: The file, named as the reader can act on it.
    /// - Returns: The sentence, without the `note  ` marker a report prefixes it with,
    ///   or `nil` when the log does explain the file.
    public func note(naming url: URL) -> String? {
        guard case let .diverged(since, _) = self else { return nil }
        return """
        \(url.path) was rewritten outside woodcase since rev \(Self.short(since.revision)) \
        (\(Self.writer(of: since)), \(ActivityEvent.clockTime(since.time))); the log has no \
        record of that change
        """
    }

    /// The row that records the outside edit, so the note fires once and never again.
    ///
    /// A transaction appends this as the first event of its own append. From then on the
    /// invariant holds again — the newest event's revision is the file's revision at the
    /// moment any woodcase write begins — and `woodcase activity` can say when the
    /// outside edit was noticed. The event carries no batch id: it belongs to no
    /// transaction, because no transaction made it.
    ///
    /// - Parameters:
    ///   - url: The file that was rewritten.
    ///   - time: When the divergence was noticed. Defaults to now.
    /// - Returns: The event to record, or `nil` when there is nothing to record.
    public func external(naming url: URL, at time: Date = Date()) -> ActivityEvent? {
        guard case let .diverged(_, found) = self else { return nil }
        return ActivityEvent(
            time: time,
            identity: ActivityEvent.unattributed,
            file: url,
            op: .external,
            revision: found
        )
    }

    // MARK: - Private

    /// A revision as a sentence quotes it: the leading eight characters.
    ///
    /// Long enough to match against a log by eye, short enough to read inside a
    /// sentence. Nothing is passed back to a verb from here, so this is prose rather
    /// than a token — the whole revision is in the log line the note points at.
    private static func short(_ revision: String) -> String {
        String(revision.prefix(8))
    }

    /// How a sentence names the writer of an event, including the one who named nobody.
    private static func writer(of event: ActivityEvent) -> String {
        event.identity == ActivityEvent.unattributed ? "unattributed" : event.identity
    }
}
