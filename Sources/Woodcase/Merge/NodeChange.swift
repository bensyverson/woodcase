//
//  NodeChange.swift
//  Woodcase
//

import Foundation

/// How one node differs between two documents, with its state on each side.
///
/// A node held by both documents carries the ``keys`` that differ; a node held by only
/// one is ``Existence/added`` or ``Existence/removed`` and carries
/// no keys, since every key of it is new or gone. Either way both ``State``s are kept, so
/// a merge reads the value of any key on either side without going back to the documents.
public struct NodeChange: Friendly {
    /// Whether the node exists on each side.
    public enum Existence: String, Friendly {
        /// Only the target document holds the node.
        case added
        /// Only the source document holds the node.
        case removed
        /// Both documents hold the node.
        case kept
    }

    /// A node as one document holds it: its own content and its place in the tree.
    public struct State: Friendly {
        /// The node with its children stripped, as ``EditableDocument/nodes`` keeps it.
        public var node: PenNode

        /// The parent's id, or `nil` for a top-level node.
        public var parentID: String?

        /// The ids of the node's children in order, or `nil` when it declares none — so
        /// `[]` is a declared `"children": []`. Always `nil` for a leaf type.
        public var children: [String]?

        /// Creates a state.
        ///
        /// - Parameters:
        ///   - node: The node, children stripped.
        ///   - parentID: The parent's id, or `nil` for a top-level node.
        ///   - children: The ordered child ids, or `nil` when none are declared.
        public init(node: PenNode, parentID: String?, children: [String]?) {
            self.node = node
            self.parentID = parentID
            self.children = children
        }
    }

    /// Creates a node change.
    ///
    /// - Parameters:
    ///   - from: The node in the source document, or `nil` if it holds none.
    ///   - to: The node in the target document, or `nil` if it holds none.
    ///   - keys: What differs, for a node both documents hold.
    public init(from: State?, to: State?, keys: Set<NodeChangeKey> = []) {
        self.from = from
        self.to = to
        self.keys = keys
    }

    /// The node in the source document, or `nil` if it was added.
    public var from: State?

    /// The node in the target document, or `nil` if it was removed.
    public var to: State?

    /// What differs about a node both documents hold; empty for an added or removed one.
    public var keys: Set<NodeChangeKey>

    /// Whether the node was added, removed or kept.
    public var existence: Existence {
        switch (from, to) {
        case (nil, _): .added
        case (_, nil): .removed
        default: .kept
        }
    }
}
