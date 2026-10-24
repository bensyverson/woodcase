//
//  PenClip+ConnectorEnds.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// Which pasted connectors keep both ends.
    ///
    /// Pen's format has no free end, so a paste never writes a connector with an end that
    /// names nothing. An end whose first id is one the paste regenerates names a pasted
    /// node, and holds when its path names a node of the clip; any other end names a node
    /// outside the paste, and holds when its path, as rewritten, names a node of the target.
    struct ConnectorEnds {
        /// The clip ids the paste gives new ids: its inserted definitions, copies and
        /// connectors, every node inside them included.
        var regenerated: Set<String>

        /// The clip, as a document.
        var clip: EditableDocument

        /// The document pasted into, as it stands.
        var target: EditableDocument

        /// The connectors, without those that would dangle.
        ///
        /// - Parameters:
        ///   - settled: The connectors as the paste writes them, in clip order.
        ///   - connectors: The same connectors as the clip holds them.
        /// - Returns: The connectors kept, the positions in `settled` they were kept from,
        ///   and the clip ids of those left out.
        func keeping(
            _ settled: [PenNode],
            from connectors: [PenNode]
        ) -> (nodes: [PenNode], kept: [Int], dropped: [String]) {
            var nodes: [PenNode] = []
            var kept: [Int] = []
            var dropped: [String] = []
            for (index, (node, source)) in zip(settled, connectors).enumerated() {
                if attaches(source, as: node) {
                    nodes.append(node)
                    kept.append(index)
                } else {
                    dropped.append(source.id)
                }
            }
            return (nodes, kept, dropped)
        }

        /// Whether both ends of a connector name a node once it is pasted.
        ///
        /// - Parameters:
        ///   - source: The connector as the clip holds it.
        ///   - pasted: The same connector as the paste writes it.
        private func attaches(_ source: PenNode, as pasted: PenNode) -> Bool {
            guard case let .connection(before) = source.kind, case let .connection(after) = pasted.kind else {
                return true
            }
            return holds(before.source.path, as: after.source.path) && holds(before.target.path, as: after.target.path)
        }

        /// Whether one end names a node once pasted.
        private func holds(_ clipPath: String, as pastedPath: String) -> Bool {
            let first = clipPath.split(separator: NodeAddress.separator, maxSplits: 1).first.map(String.init) ?? clipPath
            return regenerated.contains(first) ? Self.names(clipPath, in: clip) : Self.names(pastedPath, in: target)
        }

        /// Whether a path names a stored node or one drawn inside an instance.
        ///
        /// An end names a node by its id path (`Filled/Row2`), which for an instance
        /// inside another — one placed in a fill, say — is not its expanded id
        /// (`Filled/Row2/ItemA`), so the path is also resolved as an address of ids.
        private static func names(_ path: String, in document: EditableDocument) -> Bool {
            if document.nodes[path] != nil || document.resolve(expandedID: path) != nil { return true }
            let steps = path.split(separator: NodeAddress.separator, omittingEmptySubsequences: false).map(String.init)
            guard !steps.isEmpty, !steps.contains(where: \.isEmpty) else { return false }
            return (try? document.resolve(NodeAddress.path(steps.map { String(NodeAddress.idPrefix) + $0 }))) != nil
        }
    }
}
