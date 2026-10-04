//
//  NodeChangeKey+Content.swift
//  Woodcase
//

import Foundation

extension NodeChangeKey {
    /// The keys of a node's own content that differ between two versions of it:
    /// ``PropertyDiff``'s paths, each node extra, and a type change standing for every
    /// `kind.*` key.
    ///
    /// - Parameters:
    ///   - old: The node in the source document, children stripped.
    ///   - new: The same node in the target document, children stripped.
    /// - Returns: The content keys that differ; empty when the nodes are equal.
    static func contentDifferences(_ old: PenNode, _ new: PenNode) -> Set<NodeChangeKey> {
        var keys = Set(PropertyDiff.diffCommon(old: old.common, new: new.common).map(NodeChangeKey.property))

        let kindPaths = PropertyDiff.diffKind(old: old.kind, new: new.kind)
        if kindPaths.contains("kind.type") {
            keys.insert(.type)
        } else {
            keys.formUnion(kindPaths.map(NodeChangeKey.property))
        }

        let extraKeys = Set(old.extras.values.keys).union(new.extras.values.keys)
        keys.formUnion(extraKeys.filter { old.extras[$0] != new.extras[$0] }.map(NodeChangeKey.extra))

        assert(
            !keys.isEmpty || old == new,
            "Node \(new.id) differs in a field PropertyDiff does not compare: the vocabulary has drifted"
        )
        return keys
    }
}
