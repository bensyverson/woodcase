//
//  DocumentSession.swift
//  Woodcase
//

import Foundation

/// The one way to change a document: every edit, from every origin, through one funnel.
///
/// A session owns an ``EditableDocument`` — and, in collaborative mode, its
/// ``CRDTDocument`` — together with the author editing it, a ledger of who last wrote
/// what, and the document as last written to its file. Every change arrives through
/// ``submit(_:)`` as a ``SessionOrigin`` and comes back as one ``CommittedChange``
/// describing everything it did, so the app, the activity log and collaborators all
/// learn about an edit the same way. See <doc:Session>.
///
/// ```swift
/// let session = DocumentSession(document: parsed, author: ana, file: url, collaborative: false)
/// let change = try session.submit(.local(LocalEdit(operations: [move])))
/// pipeline.refresh(change.invalidation)
/// log.append(change.activity)
/// ```
///
/// ## Isolation
///
/// A session is a class confined to its owner — the main actor in an app, the one
/// thread of a CLI verb — and is deliberately **not** `Sendable`; `submit` is
/// synchronous. Background work takes a ``snapshot()``, which is a value.
public final class DocumentSession {
    /// Creates a session over a document.
    ///
    /// - Parameters:
    ///   - document: The document, as read from its file.
    ///   - author: Who edits through this session.
    ///   - file: The .pen file the document belongs to, or `nil` for one never saved.
    ///     Activity events are recorded only for a session with a file.
    ///   - collaborative: Whether to keep a ``CRDTDocument`` under `author`'s peer id,
    ///     so local edits come back with operations to broadcast.
    ///   - merger: What folds the file's document into this one for a
    ///     ``SessionOrigin/file(_:author:)`` submission — `.threeWay` in an app — or `nil`
    ///     for a session that never merges, which then refuses file submissions.
    public init(
        document: PenDocument,
        author: Author,
        file: URL? = nil,
        collaborative: Bool = false,
        merger: (any DocumentMerger)? = nil
    ) {
        self.author = author
        self.file = file
        self.merger = merger
        self.document = collaborative
            ? EditableDocument(from: document, peerID: author.peerID)
            : EditableDocument(from: document)
        activityBatch = nil
        mergeBase = .deferred(document, revision: nil)
        peers = [author.peerID: author]
    }

    /// Creates a session that edits a document someone else already holds.
    ///
    /// The session takes `document` as its live document, so the holder keeps reading
    /// what the session writes. This is how a transaction that hands its body an
    /// ``EditableDocument`` — ``PenFileTransaction``, ``BatchApplier`` — puts every
    /// write through the funnel without changing what the body is given. The session is
    /// never collaborative. Nothing is copied: the merge base is built from `synced` only
    /// if a merge ever asks for it.
    ///
    /// - Parameters:
    ///   - document: The document to edit in place.
    ///   - author: Who edits through this session.
    ///   - file: The .pen file the document belongs to, or `nil` to record no activity.
    ///   - synced: The document as the file holds it — what a transaction parsed — or
    ///     `nil` when there is no file state to merge against.
    ///   - activityBatch: The batch id every activity event shares, for a session that
    ///     lives for one transaction; `nil` gives each change its own.
    ///   - merger: What folds a file's document in, or `nil` to refuse file submissions.
    init(
        editing document: EditableDocument,
        author: Author,
        file: URL?,
        synced: PenDocument? = nil,
        activityBatch: String? = nil,
        merger: (any DocumentMerger)? = nil
    ) {
        self.author = author
        self.file = file
        self.merger = merger
        self.document = document
        self.activityBatch = activityBatch
        mergeBase = synced.map { MergeBase.deferred($0, revision: nil) } ?? .unknown
        peers = [author.peerID: author]
    }

    /// Who edits through this session.
    public let author: Author

    /// The .pen file the document belongs to, or `nil` for one never saved.
    public let file: URL?

    /// The live document. Read it freely; change it only through ``submit(_:)``.
    public let document: EditableDocument

    /// What folds the file's document into this one, or `nil` for a session that refuses
    /// file submissions.
    public let merger: (any DocumentMerger)?

    /// The ``CommittedChange/sequence`` of the most recent change; 0 before the first.
    public internal(set) var sequence: UInt64 = 0

    /// The sequence the file was last known to hold, from ``noteSynced(_:through:)``.
    public internal(set) var syncedSequence: UInt64 = 0

    /// Whether a dirtying change has landed since the file was last known to match.
    public var hasUnsyncedChanges: Bool {
        fileDiffersFromDocument || lastDirtyingSequence > syncedSequence
    }

    /// Applies one change and describes what it did.
    ///
    /// The change lands whole or not at all: if any part of it fails, the document,
    /// the ledger and the journal are left exactly as they were, and the error is
    /// rethrown.
    ///
    /// - Parameter origin: The change and where it comes from.
    /// - Returns: Everything the change did.
    /// - Throws: ``SessionError/notCollaborative`` for remote operations to a session
    ///   without a CRDT, ``SessionError/mergeUnavailable`` or
    ///   ``SessionError/fileStateUnknown`` for a file the session cannot merge, or the
    ///   ``EditingError`` that refused the edit.
    @discardableResult
    public func submit(_ origin: SessionOrigin) throws -> CommittedChange {
        let change: CommittedChange = switch origin {
        case let .local(edit):
            try commitLocal(edit)
        case .undo:
            try commitHistory(.undo)
        case .redo:
            try commitHistory(.redo)
        case let .remote(operations, sender):
            try commitRemote(operations, from: sender)
        case let .file(written, writer):
            try commitFile(written, author: writer)
        }
        journal?.append(change)
        return change
    }

    /// Records that the file now holds a document, as of a change.
    ///
    /// Call it after saving a ``snapshot()``, passing the snapshot's document and
    /// sequence. The written document becomes the base the next file merge diffs from.
    ///
    /// - Parameters:
    ///   - written: The document the file now holds.
    ///   - sequence: The sequence of the last change that document includes.
    public func noteSynced(_ written: PenDocument, through sequence: UInt64) {
        noteSynced(written, through: sequence, revision: nil)
    }

    /// Records that the file now holds a snapshot of this session's document — what an
    /// app calls after ``PenFileTransaction/save(_:changes:to:log:timeout:)`` reports
    /// the snapshot ``PenFileTransaction/SaveOutcome/isSynced``.
    ///
    /// The snapshot's revision becomes ``syncedRevision`` as it is, so the next save's
    /// check costs nothing here.
    ///
    /// - Parameter saved: The snapshot the file now holds.
    public func noteSynced(_ saved: DocumentSnapshot) {
        noteSynced(saved.document, through: saved.sequence, revision: saved.documentRevision)
    }

    /// The ``EditableDocument/documentRevision`` of what the file holds, as far as the
    /// session knows: the document it opened, the last snapshot it was told was saved,
    /// or the file's document from the last merge. `nil` for a session never told what
    /// its file holds.
    ///
    /// Known without work after a save or a merge; otherwise the first read builds the
    /// merge base to hash it.
    public var syncedRevision: String? {
        if case let .deferred(_, revision?) = mergeBase {
            return revision
        }
        return base?.documentRevision
    }

    /// Records what the file now holds.
    ///
    /// - Parameters:
    ///   - written: The document the file holds.
    ///   - sequence: The sequence of the last change it includes.
    ///   - revision: Its revision, when known.
    private func noteSynced(_ written: PenDocument, through sequence: UInt64, revision: String?) {
        mergeBase = .deferred(written, revision: revision)
        syncedSequence = sequence
        fileDiffersFromDocument = false
    }

    // MARK: - Internal state

    /// The batch id every activity event shares, for a session that lives for one
    /// transaction; `nil` gives each change its own.
    let activityBatch: String?

    /// Who last wrote each key.
    var ledger = ChangeLedger()

    /// The author's undo and redo stacks.
    var history = UndoHistory()

    /// Who edits on each replica the session has heard of, the session's own included:
    /// how a remote operation's peer id becomes an ``Author``. See
    /// ``noteJoined(_:)``.
    var peers: [PeerID: Author]

    /// The document as the file was last known to hold it, built into the editable base
    /// of a file merge only on first use — see ``base``.
    var mergeBase: MergeBase

    /// The sequence of the most recent change that dirtied the document.
    var lastDirtyingSequence: UInt64 = 0

    /// Whether the file is known to differ from the document whatever the sequences say:
    /// it was synced with changes a rollback has since taken back, or a file merge kept
    /// local work the file does not hold.
    var fileDiffersFromDocument = false

    /// Every change committed since the first ``checkpoint()``, which
    /// ``rollback(to:)`` unwinds; `nil` until a checkpoint is taken, so a long-lived
    /// session that never checkpoints keeps nothing here.
    var journal: [CommittedChange]?
}

/// A session is confined to its owner and must never cross an isolation boundary;
/// hand a ``DocumentSnapshot`` across instead.
@available(*, unavailable)
extension DocumentSession: Sendable {}
