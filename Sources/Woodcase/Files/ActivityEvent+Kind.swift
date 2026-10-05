//
//  ActivityEvent+Kind.swift
//  Woodcase
//

import Foundation

public extension ActivityEvent {
    /// The short verb an operation reads as in a feed.
    ///
    /// Deliberately coarser than ``EditOperation``: a reader scanning the log wants
    /// "something was set here", not which of the four property operations did it.
    /// The raw values are the wire format's `op` field, and match the CLI verbs, so a
    /// feed row and the command that would repeat it read the same — except ``place``,
    /// which a position-only `woodcase set` writes: a reader must be able to tell a
    /// nudge from a reparent (``mv``) without decoding the operation.
    ///
    /// Six kinds have no operation of their own and are only ever supplied by the
    /// caller: ``cp``, which is an insert the CLI knows was a copy, ``undo`` and
    /// ``redo``, which are whatever operation an inverse happens to be, ``external``, which is not
    /// an edit woodcase made at all — see ``LogLineage`` — and ``migrate`` and ``new``,
    /// which ``PenFileTransaction`` records for a write that is not an edit of a document.
    enum Kind: String, Friendly, CaseIterable {
        /// A property changed: `updateCommon`, `updateKind` or `setProperties` on a node,
        /// or `setDocumentProperties` on the document root.
        case set
        /// A node was inserted.
        case add
        /// A subtree was duplicated. Caller-supplied; the operation is an insert.
        case cp
        /// A node was moved to another parent, or to another index among its siblings —
        /// a reparent or a reorder, which is what `woodcase mv` does. A change of
        /// position on the canvas is ``place``.
        case mv
        /// A node was repositioned: the operation sets its `common.x`, its `common.y`,
        /// or both, and nothing else — a nudge, a freeform drag. Derived from a
        /// ``EditOperation/setProperties(_:)`` of only those paths, which is what a
        /// ``DocumentSession`` normalizes a whole-struct position change to; a write
        /// that changes anything beside the position is ``set``. Rotation and size are
        /// not placement and stay ``set``. Unlike most kinds it has no CLI verb of its
        /// own: `woodcase set x=… y=…` is the command that repeats it.
        case place
        /// A node's subtree was swapped for another, in place.
        case replace
        /// A node was deleted.
        case rm
        /// A descendant override was written on an instance.
        case override
        /// An instance was detached into independent nodes.
        case detach
        /// A variable was added, updated or removed.
        case `var`
        /// An import alias was added, updated or removed.
        case `import`
        /// A theme axis was added, updated or removed.
        case theme
        /// An earlier event's inverse was replayed. Caller-supplied.
        case undo
        /// An undone edit was put back by a ``DocumentSession`` redo. Caller-supplied: a
        /// redo replays the inverse of an undo, which looks like any other operation.
        /// Unlike ``undo`` it is an ordinary forward edit to the log-driven
        /// `woodcase undo`, which takes it back like any other row.
        case redo
        /// Somebody rewrote the file outside woodcase, and a transaction that opened it
        /// afterwards noticed. Caller-supplied by ``LogLineage``: it *records* a change
        /// rather than making one, so it names nobody, carries no inverse — there is
        /// nothing to replay — and its ``ActivityEvent/revision`` is the revision the
        /// file was found at, which is the state the outside writer left behind.
        case external
        /// The file was rewritten in the current format — `woodcase migrate`. Its bytes
        /// changed and its document did not: a migration happens as a file is read, so
        /// the event's revision is the one the file already had, and it carries no
        /// inverse. `undo` passes over it. Caller-supplied by
        /// ``PenFileTransaction/migrate(at:identity:log:timeout:effect:rewritingCurrent:diagnostics:)``.
        case migrate
        /// The file was created — `woodcase new`. The first event a file has; its
        /// revision is the empty document's, and `undo` stops at it. Caller-supplied by
        /// ``PenFileTransaction/create(at:document:identity:log:effect:)``.
        case new
        /// A session folded work that wrote no rows of its own — a file merge that kept
        /// unsaved local work, a collaborator's operations — into the document an app
        /// then saved, so no single writer's row explains the saved revision.
        /// Caller-supplied by ``PenFileTransaction/save(_:changes:to:log:timeout:)``,
        /// under the saving identity. Its ``ActivityEvent/revision`` is the saved one,
        /// its nodes are the ones the folded-in work touched, and its inverse — when the
        /// session could build one — takes the folded-in work back out. `undo` never
        /// replays it and is never stopped by it.
        case merge

        /// The kind an operation reads as, before any caller-supplied override.
        ///
        /// A ``EditOperation/setProperties(_:)`` that writes only ``placementPaths``
        /// reads as ``place``. A whole-struct ``EditOperation/updateCommon(_:)`` reads as
        /// ``set`` whatever it changed, because which of its fields differ is a question
        /// for the document: a ``DocumentSession`` derives the kind from the operation
        /// after normalizing it (``EditOperation/normalized(in:)``), so a whole-struct
        /// position change is logged as ``place`` there.
        ///
        /// - Parameter operation: The operation being recorded.
        public init(_ operation: EditOperation) {
            switch operation {
            case .insertNode: self = .add
            case .deleteNode: self = .rm
            case .moveNode: self = .mv
            case .replaceSubtree: self = .replace
            case let .setProperties(op) where !op.properties.isEmpty
                && op.properties.keys.allSatisfy(Self.placementPaths.contains):
                self = .place
            case .updateCommon, .updateKind, .setProperties, .setDocumentProperties: self = .set
            case .overrideDescendant, .overrideRoot: self = .override
            case .detachRef: self = .detach
            case .addVariable, .updateVariable, .removeVariable: self = .var
            case .addImport, .updateImport, .removeImport: self = .import
            case .addThemeAxis, .updateThemeAxis, .removeThemeAxis: self = .theme
            }
        }

        /// The property paths a ``place`` writes: a node's position, and nothing else.
        public static let placementPaths: Set<String> = ["common.x", "common.y"]
    }
}
