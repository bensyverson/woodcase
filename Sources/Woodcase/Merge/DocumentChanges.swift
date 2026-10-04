//
//  DocumentChanges.swift
//  Woodcase
//

import Foundation

/// Everything that differs between two documents, per node and per document key.
///
/// The two-way half of a three-way merge: a merge takes the changes from a base to each
/// side and resolves them key by key. Nodes are matched by id, never by content, so a
/// writer that mints new ids reads as a removal and an addition.
///
/// The walk that builds it is pruned by ``EditableDocument/revision(of:)``: a node both
/// documents hold with one revision pins an identical subtree, so nothing under it is
/// visited. Comparing two copies of a large document therefore costs a visit per root,
/// and one edit costs a visit per node along its spine and per sibling beside it. Equal
/// revisions are trusted, so a 64-bit hash collision would hide a change.
///
/// ```swift
/// let changes = DocumentChanges(from: base, to: theirs)
/// for (id, change) in changes.nodes where change.keys.contains(.parent) {
///     print(id, change.from?.parentID ?? "root", "→", change.to?.parentID ?? "root")
/// }
/// ```
public struct DocumentChanges: Friendly {
    /// The nodes that differ, keyed by id. A node that is the same on both sides, in
    /// content and in placement, is absent.
    public var nodes: [String: NodeChange]

    /// The document-level members that differ.
    public var document: Set<DocumentChangeKey>

    /// Creates a change set.
    ///
    /// - Parameters:
    ///   - nodes: The nodes that differ, keyed by id.
    ///   - document: The document-level members that differ.
    public init(nodes: [String: NodeChange] = [:], document: Set<DocumentChangeKey> = []) {
        self.nodes = nodes
        self.document = document
    }

    /// Compares two documents.
    ///
    /// Reads ``EditableDocument/revision(of:)`` on both, so it reuses — and warms — their
    /// revision caches.
    ///
    /// - Parameters:
    ///   - from: The source document, such as a merge base.
    ///   - to: The target document.
    public init(from: EditableDocument, to: EditableDocument) {
        var walk = ChangeWalk(from: from, to: to)
        self = walk.run()
    }

    /// Whether the two documents are the same.
    public var isEmpty: Bool {
        nodes.isEmpty && document.isEmpty
    }
}
