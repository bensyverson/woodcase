//
//  EditableDocument.swift
//  Woodcase
//

import Foundation
import Observation

/// A mutable, flat-store representation of a .pen document for editing.
///
/// `EditableDocument` decomposes a ``PenDocument``'s tree into a flat dictionary of
/// nodes with a separate structure map (parent/child relationships). This makes
/// structural operations (insert, delete, move) efficient and straightforward.
///
/// The document can be materialized back into a ``PenDocument`` at any time via
/// ``materialize()``, preserving full round-trip fidelity with the original.
///
/// ## Flat Store
///
/// Nodes are stored in ``nodes`` with their children stripped to `nil`. The tree
/// structure is maintained by three maps:
/// - ``children``: parent ID → ordered child IDs
/// - ``parents``: child ID → parent ID
/// - ``rootOrder``: ordered IDs of top-level nodes
///
/// ## Usage
///
/// ```swift
/// let document = try PenParser.parse(jsonData)
/// let editable = EditableDocument(from: document)
///
/// // Apply operations...
/// try editable.apply(.insertNode(EditOperation.InsertNode(node: newNode, parentID: "frame1")))
///
/// // Convert back to PenDocument for rendering
/// let updated = editable.materialize()
/// ```
///
/// ## Isolation
///
/// `EditableDocument` is **non-isolated and not `Sendable`**: it is owned by whoever
/// creates it, on whatever actor they chose. A SwiftUI editor makes one on the main
/// actor, a CLI verb makes one on its main entry point, a script host makes one
/// wherever it is called from — none of them annotates anything. What keeps that safe
/// is the missing `Sendable` conformance: the compiler refuses to let a document, its
/// caches, its ``ActivityRecorder`` or its ``CRDTDocument`` cross an isolation
/// boundary, so no two domains can ever hold the same one.
///
/// What *does* cross a boundary is a value: a ``PenDocument`` from ``materialize()``,
/// a ``CRDTOperation`` from ``applyLocal(_:)`` on its way to a peer, a
/// ``CRDTSnapshot``, an ``ActivityEvent``. Each of those is `Friendly`, and each is
/// the thing to send when the other side lives elsewhere.
@Observable
public final class EditableDocument {
    /// All nodes in the document, keyed by ID, with children stripped to `nil`.
    public internal(set) var nodes: [String: PenNode]

    /// Ordered child IDs for each container node. Only present for nodes that have children.
    public internal(set) var children: [String: [String]]

    /// Parent ID for each non-root node.
    public internal(set) var parents: [String: String]

    /// Ordered IDs of top-level (root) nodes.
    public internal(set) var rootOrder: [String]

    /// The .pen format version string, as ``PenDocument/version`` reported it: a
    /// newer minor's declared version survives every edit, and is written back.
    public var version: String

    /// Theme dimensions. Each key is a theme axis, value is an array of options.
    public var themes: [String: [String]]?

    /// Import aliases mapping to file paths or URLs.
    public var imports: [String: String]?

    /// Variable definitions, keyed by variable name.
    public var variables: [String: PenVariable]?

    /// The per-save token the format's own editor stamps on the file this document came from.
    ///
    /// Carried verbatim so ``materialize()`` round-trips it, exactly like
    /// ``version`` and ``imports``. Editing never reads it and never generates
    /// one — the editor replaces it on its next save.
    public var fileToken: String?

    /// The font files the document declares, carried verbatim so ``materialize()``
    /// writes them back. See ``PenDocument/fonts``.
    public var fonts: [PenFontDeclaration]?

    /// Root keys the file wrote that the model does not claim, carried verbatim so
    /// ``materialize()`` writes them back. Nothing edits them. See ``PenExtras``.
    public var extras: PenExtras

    /// Index of reusable component nodes, keyed by node ID.
    ///
    /// Automatically maintained as nodes are inserted, updated, or deleted.
    /// Only nodes with `common.reusable == true` appear in this registry.
    public internal(set) var componentRegistry: [String: PenNode] = [:]

    /// Called after remote CRDT operations have been applied and reconciled.
    ///
    /// This fires once per `applyRemote` call (even for batch operations).
    /// It does NOT fire for local edits (the caller observes those directly).
    /// Use this to trigger pipeline re-runs when remote peers modify the document.
    ///
    /// The closure is deliberately *not* `@Sendable` and carries no global actor. It is
    /// called synchronously, from inside `applyRemote`, in the isolation domain that
    /// owns the document — so it may touch that owner's state directly, which is the
    /// whole point of a change hook on a view model. The isolation boundary sits one
    /// step earlier, where the peer's ``CRDTOperation`` — a `Sendable` value — arrives
    /// from wherever that peer lives.
    public var onRemoteChange: (() -> Void)?

    /// Backing storage for the expansion cache.
    var _expansionCache: ExpansionCache?

    /// Backing storage for the layout cache.
    var _layoutCache: LayoutCache?

    /// Backing storage for the revision cache.
    var _revisionCache: RevisionCache?

    /// Backing storage for ``readContext``: what the document was read with, never
    /// written back.
    var _readContext: PenReadContext = .none

    /// Names this document together with the ``readContext`` it holds, unique in the
    /// process: a fresh serial is drawn for every document and on every assignment of
    /// ``readContext``. A ``SettledTree`` reuses its pieces only for the serial it was
    /// settled under, since the libraries and the font resolver are inputs no revision
    /// covers.
    var _readContextSerial = EditableDocument.nextReadContextSerial()

    /// The imported definitions and their flat store, built on first use and dropped
    /// whenever ``readContext`` changes. Keyed by the `imports` table it was built for,
    /// so an import edit rebuilds it on the next read.
    var _importCache: ImportedComponentStore?

    /// The CRDT document for collaborative editing, or `nil` if not in collaborative mode.
    ///
    /// Set when the document is created with ``init(from:peerID:)``. When non-nil,
    /// use ``applyLocal(_:)`` and ``applyRemote(_:)-(CRDTOperation)`` instead of ``apply(_:)``
    /// to keep the CRDT state synchronized.
    public internal(set) var crdtDocument: CRDTDocument?

    /// Creates an editable document by flattening a ``PenDocument`` into the flat store.
    ///
    /// - Parameter document: The source document to flatten.
    public init(from document: PenDocument) {
        nodes = [:]
        children = [:]
        parents = [:]
        rootOrder = []
        version = document.version
        themes = document.themes
        imports = document.imports
        variables = document.variables
        fileToken = document.fileToken
        fonts = document.fonts
        extras = document.extras

        flatten(document.children)

        populateComponentRegistry()
    }

    /// Creates an editable document in collaborative mode with CRDT support.
    ///
    /// The document functions identically to one created with ``init(from:)``,
    /// but also initializes a ``CRDTDocument`` for conflict-free replicated editing.
    /// Use ``applyLocal(_:)`` and ``applyRemote(_:)-(CRDTOperation)`` to keep CRDT state in sync.
    ///
    /// - Parameters:
    ///   - document: The source document to flatten.
    ///   - peerID: This peer's unique identifier for the collaborative session.
    public init(from document: PenDocument, peerID: PeerID) {
        nodes = [:]
        children = [:]
        parents = [:]
        rootOrder = []
        version = document.version
        themes = document.themes
        imports = document.imports
        variables = document.variables
        fileToken = document.fileToken
        fonts = document.fonts
        extras = document.extras

        flatten(document.children)

        populateComponentRegistry()
        crdtDocument = CRDTDocument(peerID: peerID, document: self)
    }

    /// Reconstructs a ``PenDocument`` from the flat store.
    ///
    /// The materialized document is structurally identical to the original
    /// (assuming no edits have been made), preserving node order, nesting,
    /// and all document metadata.
    ///
    /// - Returns: A fully reconstructed `PenDocument`.
    public func materialize() -> PenDocument {
        Self.buildDocument(from: FlatStoreSnapshot(
            nodes: nodes, children: children, rootOrder: rootOrder,
            version: version, themes: themes, imports: imports, variables: variables,
            fileToken: fileToken, fonts: fonts, extras: extras
        ))
    }

    /// Reconstructs a ``PenDocument`` from the flat store, performing the
    /// expensive tree reconstruction off the owner's isolation.
    ///
    /// Copying the CoW value-type dictionaries happens where the document lives and is
    /// near-instant; the tree walk then runs on a detached task, so an owner that is a
    /// UI actor is free while it happens. ``materialize()`` is the synchronous form and
    /// does the same work in place.
    ///
    /// - Parameter isolation: The actor the caller runs on, filled in by `#isolation`.
    ///   It is what lets the snapshot be taken without hopping, whichever actor owns
    ///   the document.
    /// - Returns: A fully reconstructed `PenDocument`.
    public func materializeSnapshot(
        isolation _: isolated (any Actor)? = #isolation
    ) async -> PenDocument {
        let snapshot = FlatStoreSnapshot(
            nodes: nodes, children: children, rootOrder: rootOrder,
            version: version, themes: themes, imports: imports, variables: variables,
            fileToken: fileToken, fonts: fonts, extras: extras
        )
        return await Self.buildDocumentOffActor(from: snapshot)
    }

    /// Runs ``buildDocument(from:)`` on a detached task, off whatever actor asked for it.
    ///
    /// A free function rather than the `Task.detached` written inline: Swift 6.3.3's
    /// region-based isolation checker refuses `Task.detached` inside a function that
    /// takes an `isolated (any Actor)?` parameter, with *"pattern that the region-based
    /// isolation checker does not understand how to check. Please file a bug"*.
    /// The snapshot is `Sendable`, so hoisting the detach one call out is only a
    /// workaround for the diagnostic and changes nothing about what runs where.
    ///
    /// - Parameter snapshot: The flat store to rebuild a tree from.
    /// - Returns: A fully reconstructed `PenDocument`.
    private nonisolated static func buildDocumentOffActor(
        from snapshot: FlatStoreSnapshot
    ) async -> PenDocument {
        await Task.detached { buildDocument(from: snapshot) }.value
    }

    /// Reconstructs a single subtree from the flat store.
    ///
    /// - Parameter rootID: The ID of the subtree root node.
    /// - Returns: The fully reconstructed node with all descendants.
    /// - Throws: ``EditingError/nodeNotFound(id:)`` if the ID doesn't exist.
    public func materializeSubtree(rootID: String) throws -> PenNode {
        let snapshot = FlatStoreSnapshot(
            nodes: nodes, children: children, rootOrder: [rootID],
            version: version, themes: themes, imports: imports, variables: variables,
            fileToken: fileToken, fonts: fonts, extras: extras
        )
        let doc = Self.buildDocument(from: snapshot)
        guard let node = doc.children.first else {
            throw EditingError.nodeNotFound(id: rootID)
        }
        return node
    }

    // MARK: - Private

    /// Adds a forest to the flat store, every node stripped of its inline children.
    ///
    /// Pre-order from a work list rather than by recursion: a debug build reserved
    /// 3.7 KB a level here, and a deep tree overflowed a Swift task's stack
    /// (`project/2026-09-26-debug-stack-depth.md`).
    private func flatten(_ roots: [PenNode]) {
        var pending: [(node: PenNode, parentID: String?)] = roots.reversed().map { ($0, nil) }
        while let (node, parentID) = pending.popLast() {
            nodes[node.id] = PenNode(
                id: node.id, common: node.common, kind: node.kind.withEmptyChildren(), extras: node.extras
            )

            if let parentID {
                parents[node.id] = parentID
            } else {
                rootOrder.append(node.id)
            }

            // Record children in the structure map. Store an entry even for empty arrays
            // to distinguish `children: []` from `children: nil` during materialization.
            if let declared = node.kind.declaredChildIDs {
                children[node.id] = declared
            }
            pending.append(contentsOf: node.kind.inlineChildren.reversed().map { ($0, node.id) })
        }
    }

    /// A CoW snapshot of the flat store's value-type dictionaries.
    struct FlatStoreSnapshot {
        let nodes: [String: PenNode]
        let children: [String: [String]]
        let rootOrder: [String]
        let version: String
        let themes: [String: [String]]?
        let imports: [String: String]?
        let variables: [String: PenVariable]?
        let fileToken: String?
        let fonts: [PenFontDeclaration]?
        let extras: PenExtras
    }
}
