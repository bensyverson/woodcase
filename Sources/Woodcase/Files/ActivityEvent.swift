//
//  ActivityEvent.swift
//  Woodcase
//

import Foundation

/// One line of the activity log: a single applied edit, attributed and reversible.
///
/// Every operation a ``PenFileTransaction`` commits becomes exactly one event, written
/// as one JSON object on one line of `activity.jsonl` (see ``ActivityLog``). The format
/// is a **wire format**: other tools — the viewer, `woodcase activity`, `woodcase undo`,
/// anything that tails the file — read these fields by name, so the names and their
/// meanings are a contract. <doc:WoodcaseActivityLog> documents them for those readers.
///
/// ```json
/// {"batch":"C1A0…","file":"/Users/agent/Designs/demo.pen",
///  "forward":[{"updateCommon":{"_0":{"nodeID":"jSUCH","common":{"name":"Title"}}}}],
///  "identity":"logger",
///  "inverse":[{"updateCommon":{"_0":{"nodeID":"jSUCH","common":{"name":"child-1"}}}}],
///  "nodes":["jSUCH"],"op":"set","paths":["layout-vertical/Title"],
///  "revision":"3f2a91c0d4e5b678","time":"2026-08-29T16:31:04.123Z"}
/// ```
///
/// ## Identity is a name, not a peer
///
/// ``identity`` is the plain name the writer passed as `--as` (or `$WOODCASE_AS`), not a
/// ``PeerID``: a `PeerID` is a bare UUID string with no display name, so it would say
/// nothing to a reader of the log. The CLI maps the same `--as` name to a `PeerID` when
/// it needs one for CRDT tie-breaking; the log records the readable half.
///
/// ## Times are millisecond-precise
///
/// ``time`` is held to whole milliseconds, which is the precision the ISO-8601 form on
/// the wire carries. That makes decoding a line the exact inverse of encoding one, so a
/// round-tripped event is `==` to the original rather than merely close to it.
public struct ActivityEvent: Friendly {
    /// Records one applied operation.
    ///
    /// - Parameters:
    ///   - time: When the operation was applied. Rounded to the nearest millisecond.
    ///   - identity: The writer's name, as passed to `--as`.
    ///   - file: The .pen file that was edited. Stored as an absolute path, canonicalized
    ///     by ``canonicalPath(for:)`` so that two spellings of one file compare equal.
    ///   - op: The short verb this operation reads as in a feed.
    ///   - nodes: The node ids the operation touched, from ``nodeIDs(touchedBy:)``.
    ///   - paths: Those nodes' name paths, in the same order.
    ///   - inverse: The operations that undo this one, from
    ///     ``EditableDocument/granularInverse(of:)``.
    ///   - forward: The operations as applied; empty for a row that applied nothing.
    ///   - revision: The document's ``EditableDocument/documentRevision`` *after* the
    ///     operation was applied.
    ///   - batch: An id shared by every event of one transaction, or `nil` for an event
    ///     that stands alone.
    public init(
        time: Date,
        identity: String,
        file: URL,
        op: Kind,
        nodes: [String] = [],
        paths: [String] = [],
        inverse: [EditOperation] = [],
        forward: [EditOperation] = [],
        revision: String,
        batch: String? = nil
    ) {
        self.time = Self.roundedToMilliseconds(time)
        self.identity = identity
        self.file = Self.canonicalPath(for: file)
        self.op = op
        self.nodes = nodes
        self.paths = paths
        self.inverse = inverse
        self.forward = forward
        self.revision = revision
        self.batch = batch
    }

    /// When the operation was applied, to millisecond precision, written as an
    /// ISO-8601 UTC timestamp with fractional seconds.
    public var time: Date

    /// The name of whoever made the edit — the `--as` name, not a ``PeerID``.
    public var identity: String

    /// The name an unattributed write is recorded under: nobody.
    ///
    /// A write with no `--as` and no `$WOODCASE_AS` is a real state, not a missing one.
    /// It is logged like any other write and simply names nobody, because a write that
    /// left no trace would fork the history every reader depends on — `woodcase serve`,
    /// `--follow`, the unread marks and `undo` all read this log and nothing else.
    /// The empty string is the name of that nobody: the viewer already draws it as a
    /// `?` disc titled "unattributed", and a filter for a real name never matches it,
    /// which is what keeps "everyone" and "nobody" apart.
    public static let unattributed: String = ""

    /// The absolute, canonicalized path of the .pen file that was edited.
    public var file: String

    /// The short verb this operation reads as in a feed.
    public var op: Kind

    /// The node ids the operation touched, most specific first.
    ///
    /// Empty for an operation that edits the document rather than a node — a
    /// variable, an import, a theme axis.
    public var nodes: [String]

    /// The name paths of ``nodes``, in the same order.
    ///
    /// Each path is taken from the state in which its node exists: after the operation
    /// for a node that survives it, before the operation for one it removed. So a
    /// rename records the new name and a delete records the name that was deleted.
    public var paths: [String]

    /// The operations that undo this one, in the order they must be applied.
    public var inverse: [EditOperation]

    /// The operations as they were applied, so a reader can show new values beside the
    /// old ones in ``inverse`` without reconstructing them from a later state.
    ///
    /// Empty for rows that apply nothing (`external`, `migrate`, `new`) and for lines
    /// written before the field existed; the key is omitted from the wire when empty.
    public var forward: [EditOperation]

    /// The document's revision *after* this operation was applied.
    ///
    /// `woodcase undo` compares it against the file's current revision and refuses
    /// rather than guessing when they differ.
    public var revision: String

    /// An id shared by every event of one transaction, or `nil` for a lone event.
    public var batch: String?

    // MARK: - Canonical file paths

    /// The form of a file path the log records and filters on.
    ///
    /// Standardized and with symlinks resolved, so that `/tmp/demo.pen` and
    /// `/private/tmp/demo.pen` — the same file named two ways — produce the same
    /// string, and a reader filtering by one finds events written under the other.
    ///
    /// A bundle is named by its document, whichever of the two paths the caller gave
    /// — `Design.umbra` and `Design.umbra/document.pen` record the same string — so the
    /// file watcher, which reports the `.pen` that changed, matches the log's rows.
    ///
    /// - Parameter url: The file to name: a bare `.pen`, a bundle, or a bundle's
    ///   `document.pen`.
    /// - Returns: Its absolute, canonical path.
    public static func canonicalPath(for url: URL) -> String {
        PenLocation(url).document.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// The node ids an operation touches, most specific first.
    ///
    /// The operation's subject leads; a structural operation then names the parent whose
    /// children changed, because that is the row a viewer must refresh. Operations that
    /// edit the document itself — variables, imports, theme axes, the root's own
    /// properties — touch no node and return an empty array; ``op`` and ``inverse``
    /// identify what they changed.
    ///
    /// - Parameter operation: The operation about to be applied.
    /// - Returns: The node ids it names.
    public static func nodeIDs(touchedBy operation: EditOperation) -> [String] {
        switch operation {
        case let .insertNode(op):
            if let parentID = op.parentID { [op.node.id, parentID] } else { [op.node.id] }
        case let .deleteNode(op):
            [op.nodeID]
        case let .moveNode(op):
            if let parentID = op.newParentID { [op.nodeID, parentID] } else { [op.nodeID] }
        case let .replaceSubtree(op):
            // No parent: a replace changes what is under the node, never where the
            // node sits, so the parent's row has nothing new to show.
            [op.node.id]
        case let .updateCommon(op):
            [op.nodeID]
        case let .updateKind(op):
            [op.nodeID]
        case let .setProperties(op):
            [op.nodeID]
        case let .overrideDescendant(op):
            [op.refNodeID]
        case let .overrideRoot(op):
            [op.refNodeID]
        case let .detachRef(op):
            [op.refNodeID]
        case .addVariable, .updateVariable, .removeVariable,
             .addImport, .updateImport, .removeImport,
             .addThemeAxis, .updateThemeAxis, .removeThemeAxis,
             .setDocumentProperties:
            []
        }
    }

    /// Rounds a date to the millisecond the wire format carries.
    ///
    /// Applied on the way in *and* on the way out of a line, so that an event built in
    /// memory and the same event decoded from its own line hold bit-identical dates
    /// rather than two values a rounding step apart.
    ///
    /// - Parameter date: The time to round.
    /// - Returns: The same time, to the nearest whole millisecond.
    static func roundedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}
