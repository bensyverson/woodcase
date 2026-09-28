//
//  EditableDocument+Materialize.swift
//  Woodcase
//

import Foundation

extension EditableDocument {
    /// Reconstructs a `PenDocument` tree from a flat store snapshot.
    ///
    /// - Parameter snapshot: The flat store to rebuild from.
    /// - Returns: The document, every root in ``rootOrder`` with its subtree.
    nonisolated static func buildDocument(from snapshot: FlatStoreSnapshot) -> PenDocument {
        let rootNodes = materializeNodes(snapshot.rootOrder, from: snapshot)
        return PenDocument(
            version: snapshot.version,
            themes: snapshot.themes,
            imports: snapshot.imports,
            variables: snapshot.variables,
            fileToken: snapshot.fileToken,
            fonts: snapshot.fonts,
            children: rootNodes,
            extras: snapshot.extras
        )
    }

    /// Rebuilds the trees under a list of ids, children attached, skipping any id the
    /// store has no node for.
    ///
    /// Post-order from a work list rather than by recursion, so a deep tree cannot
    /// overflow a Swift task's stack in a debug build
    /// (`project/2026-09-26-debug-stack-depth.md`).
    private nonisolated static func materializeNodes(
        _ ids: [String],
        from snapshot: FlatStoreSnapshot
    ) -> [PenNode] {
        var stack = [MaterializingLevel(node: nil, childIDs: ids)]
        while let last = stack.indices.last {
            guard stack[last].next < stack[last].childIDs.count else {
                let finished = stack.removeLast()
                guard var node = finished.node else { return finished.built }
                node.kind = node.kind.withChildren(finished.built)
                stack[stack.count - 1].built.append(node)
                continue
            }
            let id = stack[last].childIDs[stack[last].next]
            stack[last].next += 1
            guard let node = snapshot.nodes[id] else { continue }
            if let childIDs = snapshot.children[id] {
                stack.append(MaterializingLevel(node: node, childIDs: childIDs))
            } else {
                stack[last].built.append(node)
            }
        }
        return []
    }

    /// One node whose children ``materializeNodes(_:from:)`` is rebuilding.
    private struct MaterializingLevel {
        /// The node, or `nil` for the list of roots.
        let node: PenNode?

        /// The ids of its children, in order.
        let childIDs: [String]

        /// The index of the next child to rebuild.
        var next = 0

        /// The children rebuilt so far.
        var built: [PenNode] = []
    }
}
