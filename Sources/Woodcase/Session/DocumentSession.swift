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
    public init(document: PenDocument, author: Author, file: URL? = nil, collaborative: Bool = false) {
        self.author = author
        self.file = file
        self.document = collaborative
            ? EditableDocument(from: document, peerID: author.peerID)
            : EditableDocument(from: document)
        base = EditableDocument(from: document)
    }

    /// Who edits through this session.
    public let author: Author

    /// The .pen file the document belongs to, or `nil` for one never saved.
    public let file: URL?

    /// The live document. Read it freely; change it only through ``submit(_:)``.
    public let document: EditableDocument

    /// The ``CommittedChange/sequence`` of the most recent change; 0 before the first.
    public internal(set) var sequence: UInt64 = 0

    /// The sequence the file was last known to hold, from ``noteSynced(_:through:)``.
    public internal(set) var syncedSequence: UInt64 = 0

    /// Whether a dirtying change has landed since the file was last known to match.
    public var hasUnsyncedChanges: Bool {
        fileHoldsRolledBackWork || lastDirtyingSequence > syncedSequence
    }

    /// Applies one change and describes what it did.
    ///
    /// The change lands whole or not at all: if any part of it fails, the document,
    /// the ledger and the journal are left exactly as they were, and the error is
    /// rethrown.
    ///
    /// - Parameter origin: The change and where it comes from.
    /// - Returns: Everything the change did.
    /// - Throws: ``SessionError/unsupportedOrigin(_:)`` for an origin the session
    ///   cannot take yet, or the ``EditingError`` that refused the edit.
    @discardableResult
    public func submit(_ origin: SessionOrigin) throws -> CommittedChange {
        let change: CommittedChange = switch origin {
        case let .local(edit):
            try commitLocal(edit)
        case .file, .remote, .undo, .redo:
            throw SessionError.unsupportedOrigin(origin.kind)
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
        base = EditableDocument(from: written)
        syncedSequence = sequence
        fileHoldsRolledBackWork = false
    }

    // MARK: - Internal state

    /// Who last wrote each key.
    var ledger = ChangeLedger()

    /// The document as the file was last known to hold it: the base of a file merge.
    /// Kept editable so its revision cache stays warm between merges.
    var base: EditableDocument

    /// The sequence of the most recent change that dirtied the document.
    var lastDirtyingSequence: UInt64 = 0

    /// Whether the file was synced with changes a rollback has since taken back, so it
    /// differs from the document whatever the sequences say.
    var fileHoldsRolledBackWork = false

    /// Every change committed since the first ``checkpoint()``, which
    /// ``rollback(to:)`` unwinds; `nil` until a checkpoint is taken, so a long-lived
    /// session that never checkpoints keeps nothing here.
    var journal: [CommittedChange]?
}

/// A session is confined to its owner and must never cross an isolation boundary;
/// hand a ``DocumentSnapshot`` across instead.
@available(*, unavailable)
extension DocumentSession: Sendable {}
