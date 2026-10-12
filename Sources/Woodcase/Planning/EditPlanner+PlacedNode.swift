//
//  EditPlanner+PlacedNode.swift
//  Woodcase
//

import Foundation

extension EditPlanner {
    /// A node as it is drawn, with the ancestors that place and theme it.
    ///
    /// For a node with storage of its own that is the flat store's node and its parent
    /// chain. For a node inside an instance it is the node in the instance's expansion
    /// — overrides already applied — with the instance's chain above it, because the
    /// parent that lays it out and the theme it inherits are the expanded ones.
    struct PlacedNode {
        /// The node, as drawn. Its `children` may be stripped.
        var node: PenNode

        /// Its ancestors, outermost first. Their `children` may be stripped.
        var ancestors: [PenNode]

        /// The name path of its parent, for a sentence.
        var parentPath: String

        /// The node's parent, or `nil` at the document root.
        var parent: PenNode? {
            ancestors.last
        }

        /// The theme the node draws under: the first option of each axis, overlaid by
        /// every `common.theme` from the root down to the node itself.
        ///
        /// - Parameter themes: The document's theme axes.
        /// - Returns: Axis → option.
        func theme(axes themes: [String: [String]]?) -> [String: String] {
            var theme: [String: String] = [:]
            for (axis, options) in themes ?? [:] {
                theme[axis] = options.first
            }
            for placed in ancestors + [node] {
                theme.merge(placed.common.theme ?? [:]) { _, own in own }
            }
            return theme
        }

        /// A node with storage of its own.
        ///
        /// - Parameters:
        ///   - id: The node's id.
        ///   - document: The document holding it.
        /// - Returns: The node and its chain, or `nil` when the document has no such node.
        init?(node id: String, in document: EditableDocument) {
            guard let node = document.node(id: id) else { return nil }
            self.node = node
            ancestors = Self.chain(above: id, in: document)
            parentPath = document.parentID(of: id).map { document.namePath(of: $0) } ?? NodeAddress.documentRoot
        }

        /// A node inside a component instance, as the instance draws it.
        ///
        /// - Parameters:
        ///   - key: The node's `descendants` key.
        ///   - refID: The instance's `ref` node.
        ///   - document: The document holding the instance.
        /// - Returns: The node and its chain, or `nil` when the instance does not expand
        ///   to such a node.
        init?(descendant key: String, ofInstance refID: String, in document: EditableDocument) {
            let resolved = ResolvedNodeAddress.instanceDescendant(refID: refID, descendantKey: key)
            guard let expanded = try? document.expandRef(nodeID: refID).expandedNode,
                  let path = Self.path(to: document.expandedID(of: resolved), in: expanded)
            else { return nil }
            node = path[path.count - 1]
            ancestors = Self.chain(above: refID, in: document) + path.dropLast()
            // The expansion prefixes every id with the instance's, so the parent's
            // `descendants` key is its id with that prefix taken off — unless the parent
            // is the component root, which the instance's own path names.
            let prefix = refID + String(NodeAddress.separator)
            if path.count > 2, path[path.count - 2].id.hasPrefix(prefix) {
                let parentKey = String(path[path.count - 2].id.dropFirst(prefix.count))
                parentPath = document.namePath(ofDescendant: parentKey, in: refID)
            } else {
                parentPath = document.namePath(of: refID)
            }
        }

        /// Every ancestor of a flat-store node, outermost first.
        private static func chain(above id: String, in document: EditableDocument) -> [PenNode] {
            var chain: [PenNode] = []
            var cursor = document.parentID(of: id)
            while let parentID = cursor, let parent = document.node(id: parentID) {
                chain.insert(parent, at: 0)
                cursor = document.parentID(of: parentID)
            }
            return chain
        }

        /// The nodes from `root` down to the one with `id`, both ends included.
        private static func path(to id: String, in root: PenNode) -> [PenNode]? {
            var pending: [[PenNode]] = [[root]]
            while let trail = pending.popLast() {
                let last = trail[trail.count - 1]
                if last.id == id { return trail }
                for child in (last.kind.inlineChildrenIfPresent ?? []).reversed() {
                    pending.append(trail + [child])
                }
            }
            return nil
        }
    }
}
