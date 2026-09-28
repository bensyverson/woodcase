//
//  NodeLookup.swift
//  Woodcase
//

import Foundation

/// Finds the one node an address names — as the file stores it, or as it renders.
///
/// `woodcase get` is a thin shell around this, and so is a script's `doc.get`: each
/// parses its own arguments and formats its own output, and every decision about
/// *which* node an address means, and which revision goes with it, lives here where
/// both reach the same answer and a test can ask it without a process.
///
/// ## Stored versus expanded
///
/// The stored node is what an edit addresses: the flat-store entry, children stripped
/// (``TreeView`` is the structural read). The expanded node is what renders: the
/// document after ``PenRefExpander/expand(_:for:)``, so a component
/// instance appears with the component's subtree under it, overrides applied, and
/// every id prefixed by the instance's own — `Nav01/Bdg01/Cnt01`. Those are exactly
/// the ids ``TreeView`` prints and
/// ``EditableDocument/resolve(_:tags:)-(String,_)`` accepts.
///
/// An address that names a node *inside* an instance exists only in the expanded
/// world, so it is always answered from there, expansion requested or not.
public enum NodeLookup {
    /// One node, with everything a caller needs to print it or write to it.
    public struct Result: Sendable {
        /// Records one answer.
        ///
        /// - Parameters:
        ///   - address: The id-form address that resolves back to this node.
        ///   - path: The node's full name path.
        ///   - revision: The revision a write against this address must quote.
        ///   - node: The node itself.
        ///   - parameters: The parameters the node publishes, empty for most nodes.
        public init(
            address: String,
            path: String,
            revision: String,
            node: PenNode,
            parameters: [ComponentParameter] = []
        ) {
            self.address = address
            self.path = path
            self.revision = revision
            self.node = node
            self.parameters = parameters
        }

        /// The id-form address of the node: an id, or the `refID/descendantKey`
        /// id-path of an instance descendant. Resolves back to this same node.
        public let address: String

        /// The node's full name path, for a human reading the line.
        public let path: String

        /// The revision a write against this address must quote.
        public let revision: String

        /// The node itself.
        public let node: PenNode

        /// The parameters the node publishes in `common.metadata._props`, empty for a
        /// node that publishes none.
        public var parameters: [ComponentParameter] = []

        /// The answer as the `--json` report, which is the same value a script's
        /// `doc.get` returns.
        ///
        /// The parameter list is dropped when it is empty, so a consumer branches on
        /// presence rather than on an empty array.
        public var report: NodeReport {
            NodeReport(revision: revision, node: node, props: parameters.isEmpty ? nil : parameters)
        }
    }

    /// Finds the node an address names.
    ///
    /// - Parameters:
    ///   - address: The address, in any form
    ///     ``EditableDocument/resolve(_:tags:)-(String,_)`` accepts.
    ///   - document: The document to read.
    ///   - expanding: Whether to answer with the expanded node rather than the stored
    ///     one. Ignored for an address inside an instance, which has no stored node.
    /// - Returns: The node, its addresses and its revision.
    /// - Throws: ``EditingError/addressNotFound(address:nearMisses:)`` or
    ///   ``EditingError/ambiguousAddress(address:candidates:)`` when the
    ///   address names no single node.
    public static func find(
        _ address: String,
        in document: EditableDocument,
        expanding: Bool
    ) throws -> Result {
        let resolved = try document.resolve(address)
        let path = document.namePath(of: resolved)

        switch resolved {
        case let .node(id):
            guard let revision = document.revision(of: id), let stored = document.node(id: id) else {
                throw EditingError.nodeNotFound(id: id)
            }
            let node = try expanding ? expanded(resolved, in: document) : stored
            return Result(
                address: id, path: path, revision: revision, node: node,
                parameters: document.parameters(ofComponent: id)
            )

        case let .instanceDescendant(refID, key):
            // The revision is the ref's: an override to this target is stored on the
            // ref node, so that is the revision a write has to have seen.
            guard let revision = document.revision(of: refID) else {
                throw EditingError.nodeNotFound(id: refID)
            }
            let id = "\(refID)\(NodeAddress.separator)\(key)"
            let node = try expanded(resolved, in: document)
            return Result(address: id, path: path, revision: revision, node: node)
        }
    }

    // MARK: - Expansion

    /// The node a resolved address names in the document as it renders.
    ///
    /// A `ref` has no post-expansion id of its own — expansion replaces it with the
    /// component's root, keyed `refID/<component root id>` — so the id to look for is
    /// ``EditableDocument/expandedID(of:)``'s, the one mapping the layout
    /// engine, the renderer and `woodcase shot` all address the expanded tree by.
    ///
    /// - Parameters:
    ///   - resolved: What ``EditableDocument/resolve(_:tags:)-(String,_)``
    ///     returned.
    ///   - document: The document to expand and search.
    /// - Returns: The expanded node.
    /// - Throws: ``EditingError/addressNotFound(address:nearMisses:)`` when
    ///   expansion left no node under that id.
    private static func expanded(
        _ resolved: ResolvedNodeAddress,
        in document: EditableDocument
    ) throws -> PenNode {
        let id = document.expandedID(of: resolved)
        let tree = document.expanded(for: .canvas).children
        guard let found = first(in: tree, where: { $0.id == id }) else {
            throw EditingError.addressNotFound(address: id, nearMisses: [])
        }
        return found
    }

    /// The first node in pre-order that satisfies a predicate.
    private static func first(in nodes: [PenNode], where match: (PenNode) -> Bool) -> PenNode? {
        for node in nodes {
            if match(node) { return node }
            if let hit = first(in: node.kind.inlineChildren, where: match) { return hit }
        }
        return nil
    }
}
